# RustとWasmで静的ウェブページに日本語検索機能を追加する

# 概要

静的ウェブページ向け検索エンジン[tinysearch][1]を[rust_icu](https://github.com/google/rust_icu)のトークナイザ(`icu::BreakIterator`)を使って日本語対応させてみた。
また、これをmdBookに組み込み、[The Rust Programming Language 日本語版へ適用してみた][15] (chromiumのみ対応)

実装: https://github.com/tamuhey/tinysearch/tree/japanese
mdBookへの適用: https://github.com/tamuhey/mdBook/tree/tiny_search
The Rust Programming Language 日本語版への適用例: https://tamuhey.github.io/book-ja/

# tinysearch

[tinysearch][1]は静的ウェブページ向け検索エンジンです。Rust製であり、[lunr.js][2]や[elasticlunr][3]よりもインデックスファイルサイズが遥かに小さくなることが特長です。
しかし、残念なことに日本語検索に対応していません。以下のように文章を空白区切りでトークナイズし、インデックスに単語を登録しているからです:

```rust
cleanup(strip_markdown(&content))
                        .split_whitespace()
```

https://github.com/tinysearch/tinysearch/blob/e02fb592e80222033bd3b4cf6e524eefa9af4693/bin/src/storage.rs#L52

英語なら大体動きますが、日本語だとほとんど動きません。今回はこの部分を改良していき、日本語に対応させてみます。

# トークナイザ: icu::BreakIterator

では日本語を分割できるトークナイザを適当に選んでインデックスを生成すれば良いかというと、そうではありません。インデックス生成時と、実際に検索するときに用いるトークナイザの分割結果を一貫させる必要があるからです。そうでなければ単語分割結果が異なってしまい、うまくインデックスにヒットしなくなり検索精度が落ちます。

例えば[elasticlunr-rs][4]ではトークナイザに[lindera][5]を使っているので、同じ挙動のトークナイザをフロントエンドで使おうとすると、linderaの辞書である`ipadic`をフロントエンドに持ってくる必要があります。辞書はサイズがとても大きいので、ウェブページのサイズのほとんどすべてをトークナイザ用のファイルが占めることになってしまいます。これはあまりいい方法ではなさそうです。
ではフロントエンドで簡単に単語分割をするにはどうすればいいでしょうか？

実は主要なブラウザにはデフォルトで単語分割機能が入っています。試しにこの文章をダブルクリックしてみてください。空白で区切られていないにもかかわらず、文全体ではなく単語がハイライトされたはずです。
例えば、Chromiumではこの文分割機能を`Intl.v8BreakIterator`から使うことができます([参考][10])。`Intl.v8BreakIterator`はunicode-orgの[ICU][8]にある[icu::BreakIterator][7]のラッパーで、[UAX#29][19]に基づいて単語分割をします。

そして嬉しいことに、[rust_icu](https://github.com/google/rust_icu)というCrateにこの`icu::BreakIterator`が最近実装されました。つまりインデックス生成時には`rust_icu`を、フロントでは`Intl.v8BreakIterator`を使えば、インデックス生成時と検索時で一貫した単語分割結果を得られるのです。
V8依存になってしまいますが、今回はこれを使います。

# インデックス生成時のトークナイザの置き換え

まずはインデックス生成時のトークナイザを[rust_icu][6]で置き換えていきます。
こんな感じでテキストを分割する関数を作ればよいです:

```rust
use rust_icu::brk;
use rust_icu::sys;

pub fn tokenize(text: &str) -> impl Iterator<Item = &str> {
    let iter =
        brk::UBreakIterator::try_new(sys::UBreakIteratorType::UBRK_WORD, "en", text).unwrap();
    let mut ids = text.char_indices().skip(1);
    iter.scan((0, 0), move |s, x| {
        let (l, prev) = *s;
        let x = x as usize;
        if let Some((r, _)) = ids.nth(x - prev - 1) {
            *s = (r, x);
            Some(&text[l..r])
        } else {
            Some(&text[l..])
        }
    })
}
```

`rust_icu::brk::UBreakIterator`は文字境界位置のインデックスを生成するイテレータです。インデックスはバイト数ではなく文字数で返されるので、そのままtextをスライスすることはできません。`char_indices`を使い、バイト境界を求めてから部分文字列を返します。
ちなみにこれをビルドするには、nightlyのrustcとicuの開発環境をインストールする必要があります（参考: https://github.com/google/rust_icu#required ）。

# 検索時のトークナイザの置き換え

次にフロントエンドのトークナイザを置き換えます([参考][10]):

```javascript
function tokenize(text) {
    text = text.toLowerCase()
    let it = Intl.v8BreakIterator(["ja"], { type: 'word' })
    it.adoptText(text)
    let words = []
    let cur = 0, prev = 0
    while (cur < text.length) {
        cur = it.next()
        words.push(text.substring(prev, cur))
        prev = cur
    }
    return words.join(" ")
}
```

先程と同様、`Intl.v8BreakIterator`は文字境界位置を返すので、それをもとに部分文字列を抽出します。
最後に空白で結合し、tinysearchに渡します。ここはtinysearchの方を改造して、入力に単語列を取るようにしても良いかもしれません。

# Demo

以上でtinysearchの改造は終わりです。tinysearchコマンドの使い方自体は変えていないので、元のコマンドと同じ方法で検索用アセットを生成できます。
[こちら][11]が日本語対応版のデモサイトです。「日本」と打つと、ちゃんと検索結果が表示されているのがわかります。

# mdBookに日本語対応tinysearchを導入

[mdBook][13]は日本語に対応していません。検索機能には[elasticlunr-rs][4]が使われていますが、これにパッチを当てていく方針はかなり大変そうです（参考: [mdBookを日本語検索に対応させたかった](https://qiita.com/dalance/items/0a435d66e29f505faf6b))。  

そこでmdBookの検索機能をelasticlunrからtinysearchに置き換え、日本語対応させてみました。([repo][20])
試しにRustの日本語ドキュメントをビルドしたものがこちらです: https://tamuhey.github.io/book-ja/
日本語、英語両方ともうまく検索できているように見えます。  

また、インデックスとwasm moduleのファイルサイズの合計が592KBになりました。オリジナルのmdBookで生成されたインデックスファイルのサイズは5.8MBなので、約1/10程度です。tinysearchの効果が発揮されたようです。

# まとめと課題

`v8.BreakIterator`と`rust_icu::BreakIterator`を使って、tinysearchを日本語対応させてみました。
また、mdBookの検索機能をelasticlunrから今回改造したtinysearchに置き換え、試しに[日本語Rustドキュメントを生成][15]してみました。うまく日本語検索できているようです。

しかし、いくつか課題があります。

## 1. mdBookの検索結果に本文の対応箇所が表示されない

これは面倒でやっていません。インデックスファイルに本文を登録しておき、wasm module側で適当に該当箇所を返すような改造が必要です。

## 2. V8依存

今回のやりかたの一番大きな問題です。SafariやFirefoxでは完全には動きません。（検索ワードが単語分割結果と偶然一致していれば検索されます）
これについては、3つの解決策があると思います。

### `Intl.Segmenter`の実装を待つ

ECMAScriptに[Intl.Segmenter][18]が提案されています。`v8BreakIterator`とAPIは異なりますが、ベースは`icu::BreakIterator`であり分割結果は同じです。既にChrome 87には実装されており、[webkit](https://trac.webkit.org/changeset/266180/webkit)や[Firefox](https://bugzilla.mozilla.org/show_bug.cgi?id=1423593)の方でも開発が進んでいるようです。
`Intl.Segmenter`が実装されれば、これを用いてトークナイズ処理を実装することで、V8依存をなくすことができます。

### 各JSエンジンごとにそれぞれのトークナイズ処理を実装する

V8で`Intl.v8BreakIterator`を使ったように、それぞれのJSエンジンで同じように実装すれば動くかと思います。ただし、他のJSエンジンがV8と同じように`icu::BreakIterator`をAPIとして公開していればの話ですが。（ちゃんと調べてません）

### トークナイズをngramにする

トークナイズ処理をngramにすれば、V8への依存を消すことができます。
しかし、検索精度の面などで新たに問題が生じそうです。


ということで、`Intl.Segmenter`が実装されるのを気長に待ちましょう。

# Reference

- [tinysearch][1]
- [lunr][2]
- [elasticlunr][3]
- [elasticlunr-rs][4]
- [lindera][5]
- [icu][8]
- [Unicode® Standard Annex #29 UNICODE TEXT SEGMENTATION][19]
- [icu::BreakIterator][7]
- [rust_icu][6]
- [How does Chrome decide what to highlight when you double-click Japanese text? - StackOverflow][10]
- [tinysearch japanese demo][11]
- [tinysearch japanese branch][12]
- [mdBook][13]
- [mdBook with tinysearch][20]
- [Rust book][14]
- [Rust book-ja with tinysearch][15]
- [How to use ICU][17]
- [Intl.Segmenter: Unicode segmentation in JavaScript][18]

[1]:https://github.com/tinysearch/tinysearch
[2]:https://lunrjs.com/
[3]:http://elasticlunr.com/
[4]:https://github.com/mattico/elasticlunr-rs
[5]:https://github.com/lindera-morphology/lindera
[6]:https://github.com/google/rust_icu
[7]:https://unicode-org.github.io/icu-docs/apidoc/released/icu4c/classicu_1_1BreakIterator.html
[8]:https://github.com/unicode-org/icu
[9]:https://github.com/google/rust_icu
[10]:https://stackoverflow.com/questions/61672829/how-does-chrome-decide-what-to-highlight-when-you-double-click-japanese-text
[11]:https://tamuhey.github.io/tinysearch/
[12]:https://github.com/tamuhey/tinysearch/tree/japanese
[13]:https://github.com/rust-lang/mdBook
[14]:https://doc.rust-lang.org/book/
[15]:https://tamuhey.github.io/book-ja/
[16]:https://github.com/unicode-org/icu
[17]:https://unicode-org.github.io/icu/userguide/howtouseicu.html
[18]:https://github.com/tc39/proposal-intl-segmenter
[19]:http://www.unicode.org/reports/tr29/
[20]:https://github.com/tamuhey/mdbook/tree/tiny_search
