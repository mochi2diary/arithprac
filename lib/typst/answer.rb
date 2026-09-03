# frozen_string_literal: true

# Typst 生成: 解答ページのレイアウト定義。

def typ_answer_defs(scale, form)
  <<~TYP

    // 解答 1 問分(番号・答えの 2 セル)。番号は左揃え、答えは右揃え。
    // これにより「枠左線↔番号」「点線↔右番号」「右答え↔枠右線」の隙間が
    // すべて等しく(#anspad + セル内側 2pt)なる。
    #let anscell(it) = (
      align(left)[#text(size: ansfs)[#it.n]],
      align(right)[#text(size: ansfs)[#it.p]],
    )

    // 解答セルの列幅(複数の回を横に並べるため詰めている)。
    #let ansnumw = #{ans_num_width(form)}mm   // 番号(丸数字)の欄幅
    #let answ    = #{ans_width(scale, form)}mm  // 答えの欄幅

    // 解答の 1 列。番号(左揃え)・答え(右揃え)。
    #let ansminicol(items) = table(
      columns: (ansnumw, answ), stroke: none, inset: (x: 2pt, y: 1pt),
      ..items.map(it => anscell(it)).flatten())

    // 枠線・点線と数字の共通すき間。左右の外側と中央の点線まわりで同じ幅にする。
    #let anspad = 2mm

    // 解答 1 ブロック(第N回)。問題と同様に 前半 / 後半 の縦 2 列で表示。
    // 1 列レイアウトの暗算と時計は leftn が全問数になるため、後半の列と
    // 区切りの点線を出さずに 1 列で表示する。
    // ブロック幅は内容に合わせて縮める(右側の余白を作らない)。
    #let ansblock(title, items, leftn) = block(inset: (x: anspad, y: 6pt), radius: 2pt,
      stroke: 0.5pt, breakable: false, [
        #text(weight: "bold", size: 11pt)[#title]
        #v(3pt)
        #if leftn >= items.len() [
          #ansminicol(items)
        ] else [
          #grid(columns: (auto, anspad, anspad, auto), align: top,
            grid.vline(x: 2, stroke: (paint: luma(140), thickness: 0.6pt, dash: "dotted")),
            ansminicol(items.slice(0, leftn)), [], [], ansminicol(items.slice(leftn)))
        ]
      ])
  TYP
end

# 問題ページ(A4 横。2 回分ずつ)。
#   暗算(2 列): 前半 ln 問を左、残りを右に並べる。
#   暗算(1 列)・筆算・時計: 1 回分をそのまま渡す。
