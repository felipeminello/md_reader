#!/usr/bin/env bash
# Gera o build de release do macOS e envia para o App Store Connect.
#
#   tool/appstore.sh [opções]
#
#   -t, --track DESTINO  testflight (padrão: só entra no TestFlight), appstore
#                        (versão enviada para a revisão da App Store) ou o nome
#                        de um grupo do TestFlight
#   -n, --notes ARQUIVO  notas da versão, um bloco <pt-BR>…</pt-BR> por idioma
#                        (padrão: tool/release_notes.txt, se existir). No
#                        TestFlight viram o "O que testar"; na App Store, as
#                        "Novidades desta versão"
#       --draft          prepara sem enviar para revisão: a versão da App Store
#                        fica pronta para enviar pelo App Store Connect, e o
#                        build entra no grupo externo sem ir para a revisão beta
#       --skip-build     envia o .pkg que já está em build/macos/pkg, sem gerar
#                        de novo
#   -y, --yes            não pede confirmação antes de gerar e enviar
#   -h, --help           mostra esta ajuda
#
# A versão vem do pubspec.yaml (version: NOME+NÚMERO): o NOME vira o
# CFBundleShortVersionString e o NÚMERO, o CFBundleVersion. A Apple não aceita
# builds de um NOME que já foi aprovado, e no macOS o NÚMERO precisa ser maior
# que o de todo build já enviado, de qualquer NOME. Suba o número depois do +
# antes de cada envio, e o NOME depois de cada versão publicada.
#
# Só roda no macOS, com Xcode. Precisa do Team escolhido na configuração
# Release do projeto, de ITSAppUsesNonExemptEncryption e LSApplicationCategoryType
# no Info.plist, do app criado no App Store Connect e de uma chave da API do App
# Store Connect: o Issuer ID em ASC_ISSUER_ID e o arquivo em
# ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8. ASC_KEY_ID escolhe a chave
# quando há mais de uma lá, e ASC_KEY_PATH aponta para uma guardada em outro
# lugar (com ASC_KEY_ID, se o arquivo não se chamar AuthKey_<ID>.p8).

# Como preparar o Mac e o App Store Connect (uma vez só)

# 1. Assinatura: o projeto fica com o Signing Certificate em "Sign to Run
#    Locally" (CODE_SIGN_IDENTITY = -) para que `flutter build macos` funcione
#    sem certificado, inclusive no CI (.github/workflows/release.yml). Este
#    script arquiva com "Apple Development" e a exportação reassina para a loja,
#    então basta o Team: abra macos/Runner.xcworkspace no Xcode e escolha-o em
#    Runner → Signing & Capabilities → Signing (Release); o Team só no Profile
#    não serve. O Xcode precisa estar logado na conta (Xcode → Settings →
#    Accounts) para gerar os certificados "Apple Development", "Apple
#    Distribution" e "Mac Installer Distribution", que assina o .pkg.

# 2. Info.plist: macos/Runner/Info.plist declara que o app só usa criptografia
#    isenta (o HTTPS das imagens remotas); sem a chave, todo build fica parado
#    em "Conformidade de exportação ausente":
#      <key>ITSAppUsesNonExemptEncryption</key>
#      <false/>
#    e a categoria do app, sem a qual a Mac App Store recusa o envio:
#      <key>LSApplicationCategoryType</key>
#      <string>public.app-category.productivity</string>

# 3. O app: em App Store Connect → Apps → + → Novo app, plataforma macOS, com o
#    bundle ID br.dev.minello.markdown. Se ele não aparecer na lista, registre
#    antes em developer.apple.com → Certificates, IDs & Profiles → Identifiers.

# 4. A chave da API: em App Store Connect → Usuários e acesso → Integrações →
#    API do App Store Connect → Chaves da equipe, gere uma chave com acesso App
#    Manager (Developer não cria versões nem envia para revisão). Baixe o .p8,
#    que só dá para baixar uma vez, e guarde:
#      mkdir -p ~/.appstoreconnect/private_keys
#      mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
#      chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
#    O Issuer ID fica no topo da mesma página; ponha no ~/.zshrc:
#      export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 5. Para um grupo externo do TestFlight (-t "Nome do grupo"), crie o grupo e
#    preencha as informações do teste (contato e descrição do beta) na aba
#    TestFlight: a revisão beta recusa o envio sem elas.

# 6. Teste com tool/appstore.sh. HTTP 401 quer dizer Issuer ID errado ou chave
#    revogada.

set -euo pipefail

BUNDLE_ID=br.dev.minello.markdown
ASC_PLATFORM=MAC_OS
API=https://api.appstoreconnect.apple.com/v1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEYS_DIR=$HOME/.appstoreconnect/private_keys
PROJECT_DIR=$ROOT/macos
INFO_PLIST=$PROJECT_DIR/Runner/Info.plist
ARCHIVE=$ROOT/build/macos/Runner.xcarchive
PACKAGE_DIR=$ROOT/build/macos/pkg

# Estados de uma versão da App Store, nos dois campos que a API usa
# (appVersionState e o antigo appStoreState). Depois de aprovada, a versão não
# aceita builds novos.
CLOSED_STATES='ACCEPTED PENDING_APPLE_RELEASE PENDING_DEVELOPER_RELEASE PENDING_CONTRACT
  PROCESSING_FOR_APP_STORE PROCESSING_FOR_DISTRIBUTION READY_FOR_SALE READY_FOR_DISTRIBUTION
  PREORDER_READY_FOR_SALE REPLACED_WITH_NEW_VERSION DEVELOPER_REMOVED_FROM_SALE REMOVED_FROM_SALE'
EDITABLE_STATES='PREPARE_FOR_SUBMISSION READY_FOR_REVIEW DEVELOPER_REJECTED REJECTED
  METADATA_REJECTED INVALID_BINARY'

track=testflight
notes_file=$ROOT/tool/release_notes.txt
notes_given=false
draft=false
build=true
assume_yes=false

key_id=${ASC_KEY_ID:-}
key_path=${ASC_KEY_PATH:-}
issuer_id=${ASC_ISSUER_ID:-}
token=
token_expires=0
tmp=

die() { printf '\nerro: %s\n' "$*" >&2; exit 1; }
warn() { printf 'aviso: %s\n' "$*" >&2; }
step() { printf '\n==> %s\n' "$*"; }
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
in_list() {
  local item
  for item in $2; do [ "$item" = "$1" ] && return 0; done
  return 1
}

# Base64 sem padding e com o alfabeto de URL, como o JWT pede.
b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }

# O ES256 do JWT quer a assinatura crua (r e s com 32 bytes cada), mas o
# openssl entrega em DER.
der_to_raw() {
  openssl asn1parse -inform DER | awk -F: '/INTEGER/ {
    v = $NF
    while (length(v) > 64 && substr(v, 1, 2) == "00") v = substr(v, 3)
    while (length(v) < 64) v = "0" v
    printf "%s", v
  }' | xxd -r -p
}

# Assina um token de 20 minutos, o máximo que a Apple aceita.
authenticate() {
  local now header claims signature
  now=$(date +%s)
  header=$(jq -ncj --arg kid "$key_id" '{alg: "ES256", kid: $kid, typ: "JWT"}' | b64url)
  claims=$(jq -ncj --arg iss "$issuer_id" --argjson now "$now" '{
    iss: $iss,
    aud: "appstoreconnect-v1",
    iat: $now,
    exp: ($now + 1200)
  }' | b64url)
  signature=$(printf '%s.%s' "$header" "$claims" |
    openssl dgst -sha256 -sign "$key_path" | der_to_raw | b64url) ||
    die "não consegui assinar o token com $key_path"
  token=$header.$claims.$signature
  token_expires=$((now + 1200))
}

# O build e o processamento passam dos 20 minutos do token.
renew_token() { [ "$(date +%s)" -lt $((token_expires - 60)) ] || authenticate; }

# Chama a API do App Store Connect e imprime a resposta; se ela responder com
# erro, sai com a mensagem que veio. O -g impede o curl de tratar os colchetes
# de filter[...] como padrão de URL.
api() {
  local method=$1 path=$2 response status body message
  shift 2
  renew_token
  response=$(curl -sSg -X "$method" -H "Authorization: Bearer $token" -w '\n%{http_code}' "$@" "$API$path") ||
    die "sem resposta de api.appstoreconnect.apple.com"
  status=${response##*$'\n'}
  body=${response%$'\n'*}
  if [ "$status" -ge 400 ]; then
    message=$(jq -r '[.errors[]? | .detail // .title] | join(" / ")' <<<"$body" 2>/dev/null || true)
    case $status in
      401) message="$message — confira ASC_ISSUER_ID e se a chave $key_id não foi revogada" ;;
      403) message="$message — a chave precisa do acesso App Manager ou Admin" ;;
    esac
    die "$method $path → HTTP $status: ${message:-$body}"
  fi
  printf '%s\n' "$body"
}

# Corpo JSON:API para POST/PATCH, montado pelo jq com os --arg passados.
json() { jq -nc "$@"; }

# O nome do .pkg vem do nome do app, então procura em vez de fixar.
find_package() {
  local found
  found=$(find "$PACKAGE_DIR" -maxdepth 1 -name '*.pkg' 2>/dev/null || true)
  case $found in
    '') die "não há .pkg em ${PACKAGE_DIR#"$ROOT"/} $1" ;;
    *$'\n'*) die "há mais de um .pkg em ${PACKAGE_DIR#"$ROOT"/}: apague os que não servem" ;;
  esac
  package=$found
}

# Confere que o .pkg é deste app e desta versão antes de gastar tempo
# enviando. O Info.plist do app fica no Payload do componente, dentro do .pkg.
check_package() {
  local entry package_bundle package_name package_code
  rm -rf "$tmp/pkg"
  pkgutil --expand-full "$package" "$tmp/pkg" >/dev/null || die "não consegui abrir ${package#"$ROOT"/}"
  entry=$(find "$tmp/pkg" -name Info.plist | grep -E '/Payload/[^/]+\.app/Contents/Info\.plist$' | head -n 1 || true)
  [ -n "$entry" ] || die "${package#"$ROOT"/} não tem um .app com Info.plist — não parece o .pkg do app"
  package_bundle=$(plutil -extract CFBundleIdentifier raw -o - "$entry")
  package_name=$(plutil -extract CFBundleShortVersionString raw -o - "$entry")
  package_code=$(plutil -extract CFBundleVersion raw -o - "$entry")
  [ "$package_bundle" = "$BUNDLE_ID" ] || die "${package#"$ROOT"/} é do app $package_bundle, não de $BUNDLE_ID"
  [ "$package_name ($package_code)" = "$version_name ($version_code)" ] ||
    die "${package#"$ROOT"/} tem a versão $package_name ($package_code), mas o pubspec.yaml diz $version_name ($version_code) — gere de novo sem --skip-build"
}

cleanup() { [ -z "$tmp" ] || rm -rf "$tmp"; }
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case $1 in
    -t | --track)
      [ $# -ge 2 ] || die "$1 precisa de um valor"
      track=$2
      shift 2
      ;;
    -n | --notes)
      [ $# -ge 2 ] || die "$1 precisa de um valor"
      notes_file=$2
      notes_given=true
      shift 2
      ;;
    --draft) draft=true; shift ;;
    --skip-build) build=false; shift ;;
    -y | --yes) assume_yes=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "opção desconhecida: $1 (veja --help)" ;;
  esac
done
[ -n "$track" ] || die "--track não pode ser vazio"
[ "$track" != testflight ] || [ "$draft" = false ] ||
  die "--draft só vale com -t appstore ou com um grupo externo do TestFlight"

# --- Pré-requisitos --------------------------------------------------------

[ "$(uname)" = Darwin ] || die "o envio para a App Store precisa de um Mac com Xcode"
for cmd in curl jq openssl xxd xcrun xcodebuild codesign pkgutil plutil; do
  command -v "$cmd" >/dev/null || die "$cmd não está instalado"
done
tmp=$(mktemp -d)

plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$INFO_PLIST" >/dev/null 2>&1 ||
  die "${INFO_PLIST#"$ROOT"/} não declara ITSAppUsesNonExemptEncryption, e sem isso o build fica parado em \"Conformidade de exportação ausente\" (veja o passo 2 no começo deste script)"
plutil -extract LSApplicationCategoryType raw -o - "$INFO_PLIST" >/dev/null 2>&1 ||
  die "${INFO_PLIST#"$ROOT"/} não tem LSApplicationCategoryType, e a Mac App Store recusa o envio sem a categoria (veja o passo 2 no começo deste script)"

[ -n "$issuer_id" ] ||
  die "ASC_ISSUER_ID não está definido — é o Issuer ID da chave da API do App Store Connect (veja o passo 4 no começo deste script)"
if [ -z "$key_path" ]; then
  if [ -n "$key_id" ]; then
    key_path=$KEYS_DIR/AuthKey_$key_id.p8
  else
    keys=("$KEYS_DIR"/AuthKey_*.p8)
    [ -f "${keys[0]}" ] || die "não há chave da API em $KEYS_DIR (veja o passo 4 no começo deste script)"
    [ ${#keys[@]} -eq 1 ] || die "há ${#keys[@]} chaves em $KEYS_DIR: escolha uma com ASC_KEY_ID"
    key_path=${keys[0]}
  fi
fi
[ -f "$key_path" ] || die "chave da API não encontrada em $key_path (ou aponte ASC_KEY_PATH para ela)"
key_path=$(cd "$(dirname "$key_path")" && pwd)/$(basename "$key_path")
if [ -z "$key_id" ]; then
  key_id=$(basename "$key_path" .p8)
  key_id=${key_id#AuthKey_}
fi
openssl pkey -in "$key_path" -noout 2>/dev/null ||
  die "$key_path não é uma chave .p8 da API do App Store Connect"

version=$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/pubspec.yaml" | tr -d "[:space:]\"'")
version_name=${version%%+*}
version_code=${version#*+}
case $version_code in
  '' | *[!0-9]*) die "o pubspec.yaml precisa de version: NOME+NÚMERO (está '$version')" ;;
esac
[[ $version_name =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] ||
  die "a Apple só aceita um NOME de até três números, como 1.2.3 (o pubspec.yaml tem '$version_name')"

if [ "$build" = true ]; then
  command -v flutter >/dev/null || die "flutter não está no PATH"
  # O Xcode guarda o Team por configuração, e só a Release importa aqui.
  team=$(xcodebuild -project "$PROJECT_DIR/Runner.xcodeproj" -target Runner -configuration Release \
    -showBuildSettings 2>/dev/null | sed -n 's/^ *DEVELOPMENT_TEAM = //p' | head -n 1)
  [ -n "$team" ] ||
    die "o projeto macos/ não tem Team de assinatura na configuração Release: escolha um no Xcode, no bloco Signing (Release) de Runner → Signing & Capabilities (veja o passo 1 no começo deste script)"
else
  find_package "para enviar com --skip-build"
  check_package
fi

release_notes='[]'
if [ -f "$notes_file" ]; then
  release_notes=$(jq -Rs '[
    scan("<(?<lang>[A-Za-z]{2,3}(-[A-Za-z0-9]+)*)>\\s*(?<text>[\\s\\S]*?)\\s*</\\k<lang>>")
    | {language: .[0], text: .[2]}
  ]' "$notes_file")
  [ "$release_notes" != '[]' ] ||
    die "nenhum idioma em $notes_file — use um bloco <pt-BR>…</pt-BR> por idioma"
  too_long=$(jq -r '.[] | select(.text | length > 4000) | "\(.language) (\(.text | length))"' <<<"$release_notes")
  [ -z "$too_long" ] || die "a Apple aceita até 4000 caracteres por idioma: $too_long"
elif [ "$notes_given" = true ]; then
  die "$notes_file não existe"
fi

# --- App Store Connect: conferir antes de gastar tempo com o build -----------

step "Conectando ao App Store Connect"
authenticate
app=$(api GET /apps -G --data-urlencode "filter[bundleId]=$BUNDLE_ID" --data-urlencode 'fields[apps]=name,bundleId' |
  jq -r --arg id "$BUNDLE_ID" 'first(.data[] | select(.attributes.bundleId == $id) | "\(.id) \(.attributes.name)") // empty')
[ -n "$app" ] || die "não há app com o bundle ID $BUNDLE_ID no App Store Connect (veja o passo 3 no começo deste script)"
app_id=${app%% *}
app_name=${app#* }

# No macOS o número tem que crescer entre todas as versões, então a busca não
# se limita ao NOME.
used_codes=$(api GET /builds -G \
  --data-urlencode "filter[app]=$app_id" \
  --data-urlencode "filter[preReleaseVersion.platform]=$ASC_PLATFORM" \
  --data-urlencode 'fields[builds]=version' \
  --data-urlencode 'sort=-uploadedDate' \
  --data-urlencode 'limit=200' | jq -r '.data[].attributes.version')
last_code=$(sort -n <<<"$used_codes" | tail -n 1)
if [ -n "$last_code" ]; then
  last_label="o último build enviado é o ($last_code)"
  [ "$version_code" -gt "$last_code" ] ||
    die "no macOS o número precisa ser maior que o de todo build já enviado (o último é $last_code) — suba o número depois do + no pubspec.yaml"
else
  last_label="primeiro build do app"
fi

# Uma linha "id NOME estado" por versão da App Store.
store_versions=$(api GET "/apps/$app_id/appStoreVersions" -G \
  --data-urlencode "filter[platform]=$ASC_PLATFORM" --data-urlencode 'limit=200' |
  jq -r '.data[] | "\(.id) \(.attributes.versionString) \(.attributes.appVersionState // .attributes.appStoreState)"')
same_version=
editable_version=
released=false
while read -r id name state; do
  [ -n "$id" ] || continue
  ! in_list "$state" "$CLOSED_STATES" || released=true
  [ "$name" != "$version_name" ] || same_version="$id $state"
  ! in_list "$state" "$EDITABLE_STATES" || editable_version="$id $name"
done <<<"$store_versions"
if [ -n "$same_version" ] && in_list "${same_version#* }" "$CLOSED_STATES"; then
  die "a versão $version_name já foi aprovada na Mac App Store e não aceita builds novos — suba o NOME antes do + no pubspec.yaml"
fi

store_version_id=
rename_from=
group_id=
group_internal=false
group_all_builds=false
case $track in
  testflight)
    destination="TestFlight"
    ;;
  appstore)
    if [ -n "$same_version" ]; then
      in_list "${same_version#* }" "$EDITABLE_STATES" ||
        die "a versão $version_name está em ${same_version#* } na App Store — cancele o envio para revisão no App Store Connect antes de trocar o build"
      store_version_id=${same_version%% *}
      destination="App Store, versão $version_name já criada"
    elif [ -n "$editable_version" ]; then
      store_version_id=${editable_version%% *}
      rename_from=${editable_version#* }
      destination="App Store, versão $rename_from em preparação, renomeada para $version_name"
    else
      destination="App Store, versão $version_name nova"
    fi
    destination+=$([ "$draft" = true ] && echo ', sem enviar para revisão' || echo ', enviada para revisão')
    if [ "$release_notes" != '[]' ] && [ "$released" = false ]; then
      warn "a primeira versão na App Store não tem \"Novidades desta versão\": as notas ficam de fora"
      release_notes='[]'
    fi
    ;;
  *)
    groups=$(api GET /betaGroups -G --data-urlencode "filter[app]=$app_id" --data-urlencode 'limit=200')
    group=$(jq -r --arg name "$track" 'first(.data[] | select(.attributes.name == $name)
      | "\(.id) \(.attributes.isInternalGroup) \(.attributes.hasAccessToAllBuilds // false)") // empty' <<<"$groups")
    [ -n "$group" ] ||
      die "não há grupo do TestFlight chamado \"$track\" — use testflight, appstore ou um destes: $(jq -r '[.data[].attributes.name | "\"\(.)\""] | if length == 0 then "(o app não tem grupos)" else join(", ") end' <<<"$groups")"
    read -r group_id group_internal group_all_builds <<<"$group"
    if [ "$group_internal" = true ]; then
      destination="TestFlight, grupo interno \"$track\""
      [ "$group_all_builds" = false ] || destination+=" (já recebe todos os builds)"
      [ "$draft" = false ] || warn "--draft não muda nada num grupo interno, que não passa pela revisão beta"
    else
      destination="TestFlight, grupo externo \"$track\""
      destination+=$([ "$draft" = true ] && echo ', sem enviar para a revisão beta' || echo ', enviado para a revisão beta')
    fi
    ;;
esac

printf '\n  App:      %s (%s, macOS)\n  Versão:   %s (%s) — %s\n  Destino:  %s\n' \
  "$app_name" "$BUNDLE_ID" "$version_name" "$version_code" "$last_label" "$destination"
if [ "$release_notes" = '[]' ]; then
  printf '  Notas:    nenhuma\n'
else
  jq -r '.[] | "\n  [\(.language)]\n\(.text | split("\n") | map("  " + .) | join("\n"))"' <<<"$release_notes"
fi

if [ "$assume_yes" = false ]; then
  [ -t 0 ] || die "sem terminal para confirmar — rode com --yes"
  printf '\nContinuar? [s/N] '
  read -r answer
  case $answer in
    s | S | sim | y | Y | yes) ;;
    *) echo "Cancelado."; exit 0 ;;
  esac
fi

# --- Build e envio ---------------------------------------------------------

if [ "$build" = true ]; then
  rm -f "$PACKAGE_DIR"/*.pkg
  # O Flutter não gera .pkg: ele só prepara o projeto (versão do pubspec.yaml),
  # e o Xcode arquiva e exporta, compilando o Dart pelo próprio build do Runner.
  step "Preparando o projeto macOS"
  (cd "$ROOT" && flutter build macos --release --config-only)

  # O projeto assina com "-" (veja o passo 1); só o archive usa o Team.
  step "Arquivando com o Xcode"
  rm -rf "$ARCHIVE"
  xcodebuild -quiet -workspace "$PROJECT_DIR/Runner.xcworkspace" -scheme Runner -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team" CODE_SIGN_IDENTITY="Apple Development" archive

  # Os resource bundles dos plugins (SPM) saem do archive assinados com o
  # certificado de desenvolvimento, e a exportação não os reassina por estarem
  # em Contents/Resources: a Apple recusa com ITMS-90284. Como só têm recursos
  # (PrivacyInfo.xcprivacy), perdem a assinatura; a do app já os cobre.
  for bundle in "$ARCHIVE"/Products/Applications/*.app/Contents/Resources/*.bundle; do
    if codesign -d "$bundle" 2>/dev/null; then
      codesign --remove-signature "$bundle"
    fi
  done

  step "Exportando o .pkg para a App Store"
  cat >"$tmp/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>export</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$team</string>
</dict>
</plist>
EOF
  xcodebuild -quiet -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$tmp/ExportOptions.plist" \
    -exportPath "$PACKAGE_DIR" -allowProvisioningUpdates
  find_package "— o build terminou sem gerar o .pkg"
  check_package
fi

# O altool procura AuthKey_<ID>.p8 em API_PRIVATE_KEYS_DIR, então a chave ganha
# esse nome num diretório temporário, esteja onde estiver.
step "Enviando ${package#"$ROOT"/} ($(du -h "$package" | cut -f1 | tr -d ' '))"
mkdir "$tmp/private_keys"
ln -s "$key_path" "$tmp/private_keys/AuthKey_$key_id.p8"
API_PRIVATE_KEYS_DIR=$tmp/private_keys xcrun altool --upload-package "$package" -t macos \
  --apple-id "$app_id" --bundle-id "$BUNDLE_ID" \
  --bundle-version "$version_code" --bundle-short-version-string "$version_name" \
  --apiKey "$key_id" --apiIssuer "$issuer_id" ||
  die "o altool não conseguiu enviar o .pkg (a resposta da Apple está acima)"

# Sem notas e sem grupo, não há o que fazer no build: a Apple processa sozinha.
if [ "$track" = testflight ] && [ "$release_notes" = '[]' ]; then
  printf '\n%s (%s) enviada. Em alguns minutos a Apple termina de processar e ela aparece no TestFlight.\n' \
    "$version_name" "$version_code"
  exit 0
fi

step "Esperando a Apple processar o build (costuma levar de 5 a 30 minutos)"
deadline=$(($(date +%s) + 3600))
waited=false
while :; do
  build_row=$(api GET /builds -G \
    --data-urlencode "filter[app]=$app_id" \
    --data-urlencode "filter[version]=$version_code" \
    --data-urlencode "filter[preReleaseVersion.version]=$version_name" \
    --data-urlencode "filter[preReleaseVersion.platform]=$ASC_PLATFORM" \
    --data-urlencode 'fields[builds]=processingState' |
    jq -r 'first(.data[] | "\(.id) \(.attributes.processingState)") // empty')
  case ${build_row#* } in
    VALID) break ;;
    FAILED | INVALID) die "a Apple recusou o build ao processar (${build_row#* }) — o motivo chega por e-mail" ;;
  esac
  [ "$(date +%s)" -lt "$deadline" ] ||
    die "o build ainda não terminou de processar depois de uma hora — ele já foi enviado, então termine pelo App Store Connect"
  printf '.'
  waited=true
  sleep 30
done
[ "$waited" = false ] || printf '\n'
build_id=${build_row%% *}

# --- TestFlight ------------------------------------------------------------

if [ "$track" != appstore ]; then
  if [ "$release_notes" != '[]' ]; then
    step "Gravando o \"O que testar\""
    existing=$(api GET "/builds/$build_id/betaBuildLocalizations" -G --data-urlencode 'limit=50')
    while IFS= read -r locale; do
      loc_id=$(jq -r --arg l "$locale" 'first(.data[] | select(.attributes.locale == $l) | .id) // empty' <<<"$existing")
      if [ -n "$loc_id" ]; then
        api PATCH "/betaBuildLocalizations/$loc_id" -H 'Content-Type: application/json' --data "$(
          json --arg id "$loc_id" --arg l "$locale" --argjson notes "$release_notes" '{data: {
            type: "betaBuildLocalizations", id: $id,
            attributes: {whatsNew: first($notes[] | select(.language == $l) | .text)}
          }}')" >/dev/null
      else
        api POST /betaBuildLocalizations -H 'Content-Type: application/json' --data "$(
          json --arg build "$build_id" --arg l "$locale" --argjson notes "$release_notes" '{data: {
            type: "betaBuildLocalizations",
            attributes: {locale: $l, whatsNew: first($notes[] | select(.language == $l) | .text)},
            relationships: {build: {data: {type: "builds", id: $build}}}
          }}')" >/dev/null
      fi
    done < <(jq -r '[.[].language] | unique[]' <<<"$release_notes")
  fi

  if [ -n "$group_id" ] && [ "$group_all_builds" = false ]; then
    step "Adicionando o build ao grupo \"$track\""
    api POST "/betaGroups/$group_id/relationships/builds" -H 'Content-Type: application/json' \
      --data "$(json --arg id "$build_id" '{data: [{type: "builds", id: $id}]}')" >/dev/null
  fi

  if [ -n "$group_id" ] && [ "$group_internal" = false ] && [ "$draft" = false ]; then
    step "Enviando para a revisão beta"
    api POST /betaAppReviewSubmissions -H 'Content-Type: application/json' --data "$(
      json --arg id "$build_id" '{data: {
        type: "betaAppReviewSubmissions",
        relationships: {build: {data: {type: "builds", id: $id}}}
      }}')" >/dev/null
    printf '\n%s (%s) enviada para a revisão beta: o grupo "%s" recebe quando a Apple aprovar.\n' \
      "$version_name" "$version_code" "$track"
  elif [ -n "$group_id" ] && [ "$group_internal" = false ]; then
    printf '\n%s (%s) está no grupo "%s", sem revisão beta: envie pelo App Store Connect.\n' \
      "$version_name" "$version_code" "$track"
  elif [ -n "$group_id" ]; then
    printf '\n%s (%s) disponível para o grupo "%s".\n' "$version_name" "$version_code" "$track"
  else
    printf '\n%s (%s) pronta no TestFlight.\n' "$version_name" "$version_code"
  fi
  exit 0
fi

# --- App Store -------------------------------------------------------------

step "Preparando a versão $version_name na App Store"
if [ -z "$store_version_id" ]; then
  store_version_id=$(api POST /appStoreVersions -H 'Content-Type: application/json' --data "$(
    json --arg app "$app_id" --arg build "$build_id" --arg name "$version_name" --arg platform "$ASC_PLATFORM" '{data: {
      type: "appStoreVersions",
      attributes: {platform: $platform, versionString: $name},
      relationships: {
        app: {data: {type: "apps", id: $app}},
        build: {data: {type: "builds", id: $build}}
      }
    }}')" | jq -r .data.id)
else
  if [ -n "$rename_from" ]; then
    api PATCH "/appStoreVersions/$store_version_id" -H 'Content-Type: application/json' --data "$(
      json --arg id "$store_version_id" --arg name "$version_name" '{data: {
        type: "appStoreVersions", id: $id, attributes: {versionString: $name}
      }}')" >/dev/null
  fi
  api PATCH "/appStoreVersions/$store_version_id/relationships/build" -H 'Content-Type: application/json' \
    --data "$(json --arg id "$build_id" '{data: {type: "builds", id: $id}}')" >/dev/null
fi

if [ "$release_notes" != '[]' ]; then
  step "Gravando as \"Novidades desta versão\""
  localizations=$(api GET "/appStoreVersions/$store_version_id/appStoreVersionLocalizations" -G \
    --data-urlencode 'fields[appStoreVersionLocalizations]=locale' --data-urlencode 'limit=50')
  while IFS= read -r locale; do
    loc_id=$(jq -r --arg l "$locale" 'first(.data[] | select(.attributes.locale == $l) | .id) // empty' <<<"$localizations")
    if [ -z "$loc_id" ]; then
      warn "a App Store não tem o idioma $locale neste app: essa nota fica de fora"
      continue
    fi
    api PATCH "/appStoreVersionLocalizations/$loc_id" -H 'Content-Type: application/json' --data "$(
      json --arg id "$loc_id" --arg l "$locale" --argjson notes "$release_notes" '{data: {
        type: "appStoreVersionLocalizations", id: $id,
        attributes: {whatsNew: first($notes[] | select(.language == $l) | .text)}
      }}')" >/dev/null
  done < <(jq -r '[.[].language] | unique[]' <<<"$release_notes")
fi

if [ "$draft" = true ]; then
  printf '\n%s (%s) pronta na App Store: envie para revisão pelo App Store Connect.\n' "$version_name" "$version_code"
  exit 0
fi

# Um envio para revisão que ainda não foi mandado é reaproveitado: a Apple só
# deixa ter um aberto por plataforma.
step "Enviando para a revisão da App Store"
submission_id=$(api GET /reviewSubmissions -G \
  --data-urlencode "filter[app]=$app_id" \
  --data-urlencode "filter[platform]=$ASC_PLATFORM" \
  --data-urlencode 'filter[state]=READY_FOR_REVIEW' | jq -r '.data[0].id // empty')
in_submission=false
if [ -z "$submission_id" ]; then
  submission_id=$(api POST /reviewSubmissions -H 'Content-Type: application/json' --data "$(
    json --arg app "$app_id" --arg platform "$ASC_PLATFORM" '{data: {
      type: "reviewSubmissions",
      attributes: {platform: $platform},
      relationships: {app: {data: {type: "apps", id: $app}}}
    }}')" | jq -r .data.id)
else
  in_submission=$(api GET "/reviewSubmissions/$submission_id/items" -G --data-urlencode 'include=appStoreVersion' |
    jq --arg v "$store_version_id" 'any(.data[]; .relationships.appStoreVersion.data.id? == $v)')
fi
if [ "$in_submission" = false ]; then
  api POST /reviewSubmissionItems -H 'Content-Type: application/json' --data "$(
    json --arg submission "$submission_id" --arg version "$store_version_id" '{data: {
      type: "reviewSubmissionItems",
      relationships: {
        reviewSubmission: {data: {type: "reviewSubmissions", id: $submission}},
        appStoreVersion: {data: {type: "appStoreVersions", id: $version}}
      }
    }}')" >/dev/null
fi
api PATCH "/reviewSubmissions/$submission_id" -H 'Content-Type: application/json' --data "$(
  json --arg id "$submission_id" '{data: {type: "reviewSubmissions", id: $id, attributes: {submitted: true}}}')" >/dev/null

printf '\n%s (%s) enviada para a revisão da App Store.\n' "$version_name" "$version_code"
