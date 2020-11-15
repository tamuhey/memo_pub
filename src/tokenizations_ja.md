# 2つの分かち書きの対応を計算する

言語処理をする際，mecabなどのトークナイザを使って分かち書きすることが多いと思います．本記事では，異なるトークナイザの出力（分かち書き）の対応を計算する方法とその実装（[tokenizations](https://github.com/tamuhey/tokenizations)）を紹介します．
例えば以下のような，sentencepieceとBERTの分かち書きの結果の対応を計算する，トークナイザの実装に依存しない方法を見ていきます．

```
# 分かち書き
(a) BERT          : ['フ', '##ヘルト', '##ゥス', '##フルク', '条約', 'を', '締結']
(b) sentencepiece : ['▁', 'フ', 'ベル', 'トゥス', 'ブルク', '条約', 'を', '締結']

# 対応
a2b: [[1], [2, 3], [3], [4], [5], [6], [7]]
b2a: [[], [0], [1], [1, 2], [3], [4], [5], [6]]
```

# 問題の定義

先ほどの例を見ると，分かち書きが異なると以下のような差異があることがわかります

1. トークンの切り方が異なる
2. 正規化が異なる (例: ブ -> フ)
3. 制御文字等のノイズが入りうる (例: #, _)

差異が1.だけなら簡単に対処できそうです．二つの分かち書きについて，1文字ずつ上から比べていけば良いです．実際，以前spaCyに実装した`spacy.gold.align`([link](https://github.com/explosion/spaCy/pull/4526))はこの方法で分かち書きを比較します． 
しかし2.や3.が入ってくると途端にややこしくなります．各トークナイザの実装に依存して良いならば，制御文字を除いたりして対応を計算することができそうですが，あらゆるトークナイザの組み合わせに対してこのやり方で実装するのは骨が折れそうです．
[spacy-transformers](https://github.com/explosion/spacy-transformers)はこの問題に対して，[ascii文字以外を全部無視する](https://github.com/explosion/spacy-transformers/blob/88814f5f4be7f0d4c784d8500c558d9ba06b9a56/spacy_transformers/_tokenizers.py#L539)という大胆な方法を採用しています．英語ならばそこそこ動いてくれそうですが，日本語ではほとんど動きません．
ということで今回解くべき問題は，上記1~3の差異を持つ分かち書きの組みの対応を計算することです．

# 正規化

言語処理では様々な正規化が用いられます．例えば

- [Unicode正規化](https://unicode.org/reports/tr15/): NFC, NFD, NFKC, NFKD
- 小文字化
- アクセント削除

などです．上記一つだけでなく，組み合わせて用いられることも多いです．例えばBERT多言語モデルは小文字化+NFKD+アクセント削除を行なっています.

# 対応の計算法

2つの分かち書きを`A`, `B`とします．例えば`A = ["今日", "は", "いい", "天気", "だ"]`となります．以下のようにして対応を計算することができます．

1. 各トークンをNFKDで正規化し，小文字化をする
2. `A`, `B`のそれぞれのトークンを結合し，2つの文字列`Sa`, `Sb`を作る. (例: `Sa="今日はいい天気だ"`)
3. `Sa`と`Sb`の編集グラフ上での最短パスを計算する
4. 最短パスを辿り，`Sa`と`Sb`の文字の対応を取得する
5. 文字の対応からトークンの対応を計算する

要するに適当に正規化した後に，diffの逆を使って文字の対応を取り，トークンの対応を計算します．肝となるのは3で，これは編集距離のDPと同じ方法で計算でき，例えば[Myers' algorithm](http://www.xmailserver.org/diff2.pdf)を使えば低コストで計算できます．
1.でNFKDを採用したのは，Unicode正規化の中でもっとも正規化後の文字集合が小さいからです．つまりヒット率をなるべくあげることができます．例えば"ブ"と"フ"はNFKDでは部分的に対応を取れますが，NFKCでは対応を取れません．

```python
>>> a = unicodedata.normalize("NFKD", "フ")
>>> b = unicodedata.normalize("NFKD", "ブ")
>>> print(a in b)
True
>>> a = unicodedata.normalize("NFKC", "フ")
>>> b = unicodedata.normalize("NFKC", "ブ")
>>> print(a in b)
False
```

# 実装

実装はこちらに公開しています: [GitHub: tamuhey/tokenizations](https://github.com/tamuhey/tokenizations)

中身はRustですが，Pythonバインディングも提供しています．Pythonライブラリは以下のように使えます．

```console
$ pip install pytokenizations
```

```python
>>> import tokenizations
>>> tokens_a = ['フ', '##ヘルト', '##ゥス', '##フルク', '条約', 'を', '締結']
>>> tokens_b = ['▁', 'フ', 'ベル', 'トゥス', 'ブルク', '条約', 'を', '締結']
>>> a2b, b2a = tokenizations.get_alignments(tokens_a, tokens_b)
>>> print(a2b)
[[1], [2, 3], [3], [4], [5], [6], [7]]
>>> print(b2a)
[[], [0], [1], [1, 2], [3], [4], [5], [6]]
```

# 終わりに

先日，[Camphr](https://qiita.com/tamurahey/items/53a1902625ccaac1bb2f)という言語処理ライブラリを公開しましたが，このライブラリの中で`pytokenizations`を多用しています．transformersとspaCyの分かち書きの対応を計算するためです．おかげで，2つのライブラリを簡単に結合できるようになり，モデルごとのコードを書く必要がなくなりました．地味ですが実用上非常に役に立つ機能だと思います．
