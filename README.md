# Arithprac: 計算プリント生成ツール

[English](README.en.md)

幼児向け／小学生向けの計算プリント(PDFファイル)を自動生成するツールです。

ツールではなく生成されたプリントに興味がある方のほうが多いと思いますので，本 README ではプリントの説明を行います。

## はじめに

あくまで自分の子供にやらせているプリントを公開している位置づけのものなので，急に破壊的な仕様変更が入ります（公開されているプリントの形式が予告なく変更されます）。

プリントおよびプログラムを使用した結果や，プリントが急に提供されなくなったことなどについての責任は一切負いません。あらかじめご了承ください。

プリントのPDFファイルは自動生成システムが正常動作していれば1日に1回夜間に更新され，最新のファイルと，1つ前のファイルが掲載されます。

本プログラムおよび本プログラムで生成して GitHub に置いてある計算プリント（PDFファイル）のライセンスには MIT License を適用します（埋め込みフォントを除く）ので，ファイルのコピーや印刷・配布は自由かつ無償です。

## プリントの種別

### たしざん（暗算）

- 片手の指で数えられる範囲 + 片手の指で数えられる範囲
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-1-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-1-1-prev.pdf)
- 足した答えが両手で数えられる範囲
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-1-2.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-1-2-prev.pdf)
- 1桁 + 1桁（繰り上がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-1-5.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-1-5-prev.pdf)

### ひきざん（暗算）

- 両手の指で数えられる範囲の引き算
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-2-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-2-1-prev.pdf)
- 結果が10以下の引き算（繰り下がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-2-2.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-2-2-prev.pdf)

### たしひき混合（暗算）

- 1桁 + 1桁（繰り上がりあり）／結果が10以下の引き算（繰り下がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-5-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-5-1-prev.pdf)

### 小数かけざん（暗算）

- 最大2桁 x 1桁
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-8-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-8-1-prev.pdf)

### かけざん（暗算）

- 九九 （2x2 .. 9x9）順番通り
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-3-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-3-1-prev.pdf)
- 九九の範囲 （2x2 .. 9x9）ランダム
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-3-2.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-3-2-prev.pdf)
- 2桁 × 2桁 （1は半分だけ出現）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-3-6.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s1-3-6-prev.pdf)

### たしざん（筆算）

試しに作ってはみたものの，4歳児が書き込むには字が小さすぎる気がする（未確認）。

- 2桁 + 1桁 （繰り上がりなし）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-1-prev.pdf)
- 2桁 + 1桁 （十の位への繰り上がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-2.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-2-prev.pdf)
- 2桁 + 2桁（十の位への繰り上がりあり，百の位への繰り上がりなし）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-3.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-3-prev.pdf)
- 最大3桁 + 2桁（十・百の位への繰り上がりあり，千の位への繰り上がりなし）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-4.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-4-prev.pdf)
- 3桁 + 最大3桁（繰り上がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-5.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-1-5-prev.pdf)

### ひきざん（筆算）

こちらも試しに作ってはみたものの…

- 2桁 - 1桁 （繰り下がりなし）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-1-prev.pdf)
- 2桁 - 1桁 （繰り下がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-2.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-2-prev.pdf)
- 最大3桁 - 最大3桁 （十の位の繰り下がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-3.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-3-prev.pdf)
- 最大3桁 - 最大3桁 （百・十の位の繰り下がりあり）
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-4.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s2-2-4-prev.pdf)

### 時計（読み）

- ○時ちょうど
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-1.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-1-prev.pdf)
- ○時(0|15|30|45)分
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-2.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-2-prev.pdf)
- ○時(5の倍数)分
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-3.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-3-prev.pdf)
- ○時○○分
    - [最新ファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-4.pdf) [1つ前のファイル](https://github.com/mochi2diary/arithprac/releases/download/latest/s3-1-4-prev.pdf)

## おわりに

Claude にちゃちゃっと書かせただけの簡単なプログラム（と生成物）なので，気に入らない点があればご自身で修正されるか同様のものを新たに作成されるのがよいと思います。
