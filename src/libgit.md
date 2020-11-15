## commit dateでファイルをソートする

- how to
    - 対象のpathsをrepo.indexで取得
        - これはglobとかでもいい
    - revwalkをtime orderで取得
    - 各commitに対してtreeを取得し、すべてのpathについて`get_path`でblob取得
    - blob idが異なっていればそのcommitで変更があったということがわかる
- logの実装を見たが、diffoptsにpathsを設定してparentsとの差分を取得していたので代替似たようなことをしなければならないらしい
    