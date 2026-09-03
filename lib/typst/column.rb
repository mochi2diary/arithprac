# frozen_string_literal: true

# Typst 生成: 筆算のレイアウト定義。

def typ_column_defs(scale)
  s = COLUMN_SCALES[scale]
  <<~TYP

    // --- 寸法(スケール: #{scale}) ---
    #let digw    = #{s[:digw]}mm    // 数字 1 桁分のセル幅(1 桁 = 横 1 セル)
    #let digha   = #{s[:digh_a]}mm    // 被加数行のセル高さ
    #let dighb   = #{s[:digh_b]}mm    // 加数行のセル高さ
    #let digfont = "#{COLUMN_DIGIT_FONT}"  // 数字・演算子のフォント(本文とは別)
    #let digfs   = #{s[:digfs]}pt   // 数字・演算子のフォントサイズ
    #let ruleh   = #{s[:ruleh]}mm   // 横線行の高さ
    #let rulethk = #{s[:rulethk]}pt  // 横線の太さ
    #let rpadx   = #{s[:rpad_x]}mm    // リージョン内の左右の余白
    #let rpadtop = #{s[:rpad_top]}mm    // 同・上の余白(繰り上がりを書き込む分)
    #let numfs   = 12pt   // 問題番号(丸数字)のフォントサイズ

    // 1 文字 = 1 セル。上下左右中央揃え。
    #let digcell(c) = align(center + horizon)[#text(font: digfont, size: digfs)[#c]]

    // 数字のクラスタ配列を nd 桁分のセル配列にする(右詰め。足りない上位桁は空セル)。
    // 全角は 1 文字 3 バイトのため、桁数は必ずクラスタ数で数える(str.len() はバイト数)。
    #let digcells(cs, nd) = range(nd - cs.len()).map(i => []) + cs.map(c => digcell(c))

    // 筆算 1 問。最左は演算子列、その右に数字列(桁数は被加数/加数の多いほう)。
    // 行は上から 被加数 / 加数 / 横線 / 解答記入。セル間に空白は作らない。
    #let colprob(a, b, op) = {
      let ca = str(a).clusters()
      let cb = str(b).clusters()
      let nd = calc.max(ca.len(), cb.len())
      let nc = nd + 1  // 演算子列の分
      grid(
        columns: range(nc).map(i => digw),
        // 解答記入行(最下行)は 1fr。リージョンの余った高さを書き込み欄にする。
        rows: (digha, dighb, ruleh, 1fr),
        stroke: none, inset: 0pt,
        [], ..digcells(ca, nd),
        digcell(op), ..digcells(cb, nd),
        ..range(nc).map(i => align(horizon)[#line(length: 100%, stroke: rulethk)]),
        ..range(nc).map(i => []),
      )
    }

    // 1 リージョン(1 問分)。問題は右寄せ、番号は左寄せで被加数行と同じ位置(上揃え)に置く。
    // 行を 1fr にして、問題本体(解答記入行が 1fr)が残り高さいっぱいに広がるようにする。
    #let region(it) = block(width: 100%, height: 100%,
      inset: (top: rpadtop, right: rpadx, left: rpadx),
      grid(columns: (auto, 1fr), rows: (1fr), align: (left + top, right + top),
        text(size: numfs)[#it.n],
        colprob(it.a, it.b, it.op)))
  TYP
end

# 時計盤の作図(clock.typ の内容を組み込んだもの。外部パッケージは使わない)。
# #clock(hour, minute, size: ..) で 1 つ描く。
#   hour   : 0-23 の整数(内部で 12 時間表記に変換)
#   minute : 0-59 の整数
#   size   : 全体の直径   ink: 線・文字の色(モノクロなので既定は black)
