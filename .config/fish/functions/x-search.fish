function x-search --description 'Hermes Agent x_search で X を検索する'
    if not command -q hermes
        echo "hermes が見つかりません。dotfiles で導入する場合は ./install.sh または ./install.sh hermes を実行してください。" >&2
        return 127
    end

    if test (count $argv) -eq 0
        echo "使い方: x-search <検索したい内容>" >&2
        return 2
    end

    if not test -f "$HOME/.hermes/auth.json"
        echo "xAI OAuth 認証が未設定の可能性があります。先に hermes auth add xai-oauth または hermes model を実行してください。" >&2
    end

    set -l query (string join ' ' -- $argv)
    set -l prompt "x_search toolを使ってXを検索してください。terminal、shell、xurl、web_search、browserは使わないでください。検索クエリ: $query。回答は日本語で、要点、根拠、citations、credential_source、degradedを含めてください。"

    env HERMES_INFERENCE_PROVIDER=xai-oauth HERMES_INFERENCE_MODEL=grok-4.3 hermes --provider xai-oauth --model grok-4.3 -t x_search -z "$prompt"
end
