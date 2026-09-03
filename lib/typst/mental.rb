# frozen_string_literal: true

# Typst 生成: 暗算(2列/1列)のレイアウト定義。

def typ_mental_defs(scale)
  oneline?(scale) ? typ_oneline_defs(scale) : typ_twocol_defs(scale)
end

# 問題(暗算・1 列)の定義。1 問 = 4 セルの行(番号・式・等号・解答欄)。
# 式は項や演算子ごとにセルへ割り付けず、1 つの文字列として 1 セルに収める
# (項数・桁数・演算子が問題ごとに異なってよいフリーフォーマット)。
def typ_oneline_defs(scale)
  s = SCALES[scale]
  <<~TYP

    // --- 寸法(スケール: #{scale} / 1 列レイアウト) ---
    #let boxw  = #{s[:boxw]}mm   // 解答欄(横長の□)の幅。1 列ぶんの幅を活かす。
    #let boxh  = #{s[:boxh]}mm    // 解答欄の高さ(手書き用に本文より少し大きめ)
    #let numw  = 6mm    // 問題番号の欄幅
    #let numgap = 5mm   // 問題番号と式のあいだの空き
    #let eqw   = 5mm    // 等号の欄幅
    #let exprfs = #{s[:exprfs]}pt  // 式・等号のフォントサイズ

    #let ansbox = box(width: boxw, height: boxh, stroke: 0.7pt, radius: 1pt)

    // 1 問分の行(4 セル)。式は左揃え(桁数が伸びても左端がそろう)。
    #let probrow(n, expr) = (
      align(right)[#text(size: 12pt)[#n]],
      align(left)[#h(numgap)#text(size: exprfs)[#expr]],
      align(center)[#text(size: exprfs)[=]],
      align(left + horizon)[#ansbox],
    )

    // 式の列を 1fr にして残り幅を吸収させ、等号と解答欄を右端にそろえる。
    // 式は左揃えのままなので、行ごとに左端・等号・解答欄の位置がそろう。
    #let probtable(items) = table(
      columns: (numw, 1fr, eqw, auto),
      stroke: none,
      align: horizon,
      inset: (x: 2pt, y: #{s[:inset_y]}pt),
      ..items.map(it => probrow(it.n, it.expr)).flatten()
    )

    // A5 1 枚分(1 回分)。全問を上から下へ 1 列に並べる(列間の点線は引かない)。
    #let probset(title, items) = block(width: 100%, height: 100%, [
      #probhead(title)
      #grid(columns: (1fr), align: top, probtable(items))
    ])
  TYP
end

# 問題(暗算・2 列)の定義。1 問 = 6 セルの行、A5 1 枚は前半/後半の 2 列。
def typ_twocol_defs(scale)
  s = SCALES[scale]
  <<~TYP

    // --- 寸法(スケール: #{scale}) ---
    #let boxw = #{s[:boxw]}mm   // 解答欄(横長の□)の幅
    #let boxh = #{s[:boxh]}mm    // 解答欄の高さ(手書き用に本文より少し大きめ)
    #let numw = 6mm    // 問題番号の欄幅
    #let valw = 10mm   // 被演算数・演算数の欄幅(3 桁でも右揃えで収まる)
    #let opw  = 5mm    // 演算子(+, ×, =)の欄幅
    #let valfs = #{s[:valfs]}pt  // 数値・等号のフォントサイズ
    #let opfs  = #{s[:opfs]}pt  // 演算子(+/×)のフォントサイズ

    #let ansbox = box(width: boxw, height: boxh, stroke: 0.7pt, radius: 1pt)

    // 1 問分の行(6 セル)。数値は右揃えで右端をそろえる。
    #let probrow(n, a, b, op) = (
      align(right)[#text(size: 12pt)[#n]],
      align(right)[#text(size: valfs)[#a]],
      align(center)[#text(size: opfs)[#op]],
      align(right)[#text(size: valfs)[#b]],
      align(center)[#text(size: valfs)[=]],
      align(left + horizon)[#ansbox],
    )

    #let probtable(items) = table(
      columns: (numw, valw, opw, valw, opw, auto),
      stroke: none,
      align: horizon,
      inset: (x: 2pt, y: #{s[:inset_y]}pt),
      ..items.map(it => probrow(it.n, it.a, it.b, it.op)).flatten()
    )

    // A5 1 枚分(1 回分)。左に前半、右に後半を並べる。
    #let probset(title, left, right) = block(width: 100%, height: 100%, [
      #probhead(title)
      // 左(前半)と右(後半)を区切る点線。線をやや左に寄せ、右列の番号との隙間を広めに。
      #grid(columns: (1fr, 1.5mm, 6mm, 1fr), align: top,
        grid.vline(x: 2, stroke: (paint: luma(140), thickness: 0.6pt, dash: "dotted")),
        probtable(left), [], [], probtable(right))
    ])
  TYP
end

# 問題(筆算)の定義。1 リージョンに 1 問(右上寄せ)を配置する。
# 番号はリージョンの左上に置く。リージョン割り自体は typ_region_defs が行う。
