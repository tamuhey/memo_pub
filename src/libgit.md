# commit dateでファイルをソートする

gitのファイルをcommit dateでソートするのは結構めんどくさい

- how to
    - 対象のpathsを`repo.index`でとってくる
        - これはglobとかでもいい
    - revwalkをtime orderで作る
    - 各commitに対してtreeを取得し、すべてのpathについて`get_path`でblobを取得
    - blob idが以前のcommitと異なっていればそのcommitで変更があったということがわかる
- example/logの実装を見たが、diffoptsにpathsを設定してparentsとの差分を取得していたのでだいたい似たようなことをしなければならないらしい
    - そもそもblobには日時に関するメタデータが入っていないので、commitからそれを持ってくるしかない
- sample: https://github.com/tamuhey/libgit2_example/blob/master/src/bin/ls_tree.rs
    