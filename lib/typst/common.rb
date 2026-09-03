# frozen_string_literal: true

# Typst 生成の共通部(前文・問題/解答・リージョン割り・build_typst)。

# ---- Typst 生成 --------------------------------------------------------

# レイアウトの種別。筆算は :column、時計は :clock、
# 暗算は 2 列(:mental)か 1 列(:oneline)。
def prob_kind(form, scale)
  return form if %i[column clock].include?(form)

  oneline?(scale) ? :oneline : :mental
end

# 1 列レイアウトの問題(式)。数値と演算子の間に空白を入れる(例: 0.4 × 0.6)。
def prob_expr(prob)
  "#{dec_str(prob[:a])} #{OP_SYM[prob[:op]]} #{dec_str(prob[:b])}"
end

# 問題テーブルのセル配列(Typst の array of dict リテラル)。
# 筆算(:column)は数字・演算子とも全角で渡す。暗算(:mental / :oneline)は半角のまま
# (1 つのテキストランで組むため、全角にすると字送りが欄幅を超える)。
# 数値は Ruby 側で文字列にしてから渡す(小数を Typst の float にすると表記が変わる)。
def typ_problems(items, kind = :mental)
  '(' + items.map { |p|
    case kind
    when :column
      %{(n: "#{circled(p[:n])}", a: "#{zen_digits(p[:a])}", b: "#{zen_digits(p[:b])}", op: "#{OP_SYM_ZEN[p[:op]]}")}
    when :oneline
      %{(n: "#{circled(p[:n])}", expr: "#{prob_expr(p)}")}
    when :clock
      # 時計は「じ」(h)・「ふん」(m)と、解答欄に「ふん」を出すか(showmin)を渡す。
      %{(n: "#{circled(p[:n])}", h: #{p[:a]}, m: #{p[:b]}, showmin: #{p[:minute]})}
    else
      %{(n: "#{circled(p[:n])}", a: "#{dec_str(p[:a])}", b: "#{dec_str(p[:b])}", op: "#{OP_SYM[p[:op]]}")}
    end
  }.join(', ') + ',)'
end

# 解答の表示文字列。時計の解答は文字列(例: 3 じ 30 ふん)、それ以外は数値。
def ans_str(prob)
  prob[:ans].is_a?(String) ? prob[:ans] : dec_str(prob[:ans])
end

# 解答テーブルのセル配列
def typ_answers(items)
  '(' + items.map { |p| %{(n: "#{circled(p[:n])}", p: "#{ans_str(p)}")} }.join(', ') + ',)'
end

# 暗算・筆算で共通の前文(フォント・見出し・切り取り線・A4 横 1 ページの組み方)。
def typ_preamble(title_text, stage_name, form, tag)
  <<~TYP
    // 自動生成ファイル (arithprac.rb) — 直接編集しないでください。
    #set text(font: "#{body_font}", size: 12pt, lang: "#{lang}")
    // アポストロフィ(英語の o'clock)を約物に置き換えない。日本語フォントの
    // 曲がりアポストロフィは全角幅で、前後に不自然な空きができるため。
    #set smartquote(enabled: false)

    // ステージ名(ステージ指定時のみ。空文字なら非表示)。「第N回」の左に置く。
    #let stagename = "#{stage_name}"

    #let ansfs = 10pt  // 解答の文字サイズ(人間が読みやすい固定サイズ)

    // --- ページ下端のタグ(印刷後に問題と解答を対応づけるための識別子) ---
    // 用紙の左下から 横 #{TAG_MARGIN_X}mm / 縦 #{TAG_MARGIN_Y}mm。本文マージンの外側に置く。
    #let tag = "#{tag}"
    #let tagmark(dx) = place(bottom + left, dx: dx, dy: -#{TAG_MARGIN_Y}mm)[
      #text(size: #{TAG_FS}pt, fill: luma(#{TAG_LUMA}))[#tag]]
    // 問題(A4 横)は A5×2 に切るため、左右それぞれの左下に入れる。
    #let tagprob = { tagmark(#{TAG_MARGIN_X}mm); tagmark(#{A5_WIDTH + TAG_MARGIN_X}mm) }
    // 解答(A4 縦)は左下 1 箇所。
    #let tagans = tagmark(#{TAG_MARGIN_X}mm)

    // A5 1 枚(1 回分)の見出し。大見出し・回・名前・得点、最後に問題本体との空き。
    #let probhead(title) = [
      #align(center)[#text(size: 18pt, weight: "bold")[#{title_text}]]
      #v(3pt)
      #align(center)[#text(size: 10pt)[
        #if stagename != "" [#stagename #h(6mm)]#title #h(8mm) #{t(:name)} #box(width: 28mm, stroke: (bottom: 0.5pt))[] #h(4mm) #{t(:score)} #box(width: 14mm, stroke: (bottom: 0.5pt))[]
      ]]
      #v(#{HEAD_GAP[form]}pt)
    ]

    // 中央の切り取り線(A4 横を A5×2 に分けるための目印)
    #let cutline = place(top + center,
      rect(width: 0pt, height: 100%,
        stroke: (left: (paint: luma(150), thickness: 0.6pt, dash: "dashed"))))

    // A4 横 1 ページ = A5 2 枚(2 回分)
    #let sheetpair(setA, setB) = {
      grid(columns: (1fr, 1fr), column-gutter: 10mm, setA, setB)
      cutline
    }
  TYP
end

# 問題(暗算)の定義。スケールにより 2 列レイアウトか 1 列レイアウトを出力する。
def typ_region_defs(num)
  rows, cols = REGION_SHAPES[num]
  <<~TYP

    // リージョンの区切り点線(外周には引かない)
    #let regionline = (paint: luma(140), thickness: 0.4pt, dash: "dotted")

    // 問題本体。#{num} 問 = 縦 #{rows} 個 × 横 #{cols} 列に等分割(番号は行優先)。
    #let regiongrid(items) = grid(
      columns: range(#{cols}).map(i => 1fr),
      rows: range(#{rows}).map(i => 1fr),
      stroke: none, inset: 0pt,
      ..range(1, #{cols}).map(i => grid.vline(x: i, stroke: regionline)),
      ..range(1, #{rows}).map(j => grid.hline(y: j, stroke: regionline)),
      ..items.map(it => region(it)),
    )

    // A5 1 枚分(1 回分)。見出しは auto、残り(1fr)をリージョン割りに与える。
    // (見出しの高さを差し引くため、外側を grid(rows: (auto, 1fr)) で組む)
    #let probset(title, items) = block(width: 100%, height: 100%,
      grid(rows: (auto, 1fr), columns: (100%), row-gutter: 0pt, inset: 0pt,
        probhead(title), regiongrid(items)))
  TYP
end

# 解答(A4 縦)。暗算・筆算・時計で共通。
def typ_problem_pages(sets, num, kind, scale)
  ln = left_count(num, scale)
  probset_args = lambda do |set, n|
    if kind == :mental
      "\"#{t(:set_no, n: n)}\", #{typ_problems(set[0...ln])}, #{typ_problems(set[ln...num])}"
    else
      "\"#{t(:set_no, n: n)}\", #{typ_problems(set, kind)}"
    end
  end
  out = +''
  (0...sets.size).step(2) do |i|
    a = probset_args.call(sets[i], i + 1)
    b = probset_args.call(sets[i + 1], i + 2)
    out << %{\n#sheetpair(\n  probset(#{a}),\n  probset(#{b}),\n)\n}
    out << "#pagebreak()\n" if i + 2 < sets.size
  end
  out
end

def build_typst(sets, num, title_text, stage_name, scale, form, tag)
  kind = prob_kind(form, scale)
  out = +''
  out << typ_preamble(title_text, stage_name, form, tag)
  out << case form
         when :column then typ_column_defs(scale) + typ_region_defs(num)
         when :clock  then typ_clock_face_defs + typ_clock_defs + typ_region_defs(num)
         else typ_mental_defs(scale)
         end
  out << typ_answer_defs(scale, form)
  out << <<~TYP

    // ================= 問題(A4 横) =================
    #set page(paper: "a4", flipped: true, margin: (x: 6mm, y: 8mm), background: tagprob)
  TYP
  out << typ_problem_pages(sets, num, kind, scale)

  # ================= 解答(A4 縦) =================
  # 見出しは「大見出し・ステージ名・解答」を言語ごとの区切り字でつないだもの。
  # Typst 側で組み立てると、区切り字の "- " が行頭に来たときにリストとして
  # 解釈されてしまうため、Ruby 側で 1 つの文字列にしてから渡す。
  ans_head = [title_text, stage_name, t(:answers)].compact.join(t(:ans_head_sep))
  out << <<~TYP

    #set page(flipped: false, margin: (x: 10mm, y: 10mm), background: tagans)
    #align(center)[#text(size: 16pt, weight: "bold")[#{ans_head}]]
    #v(6pt)
    #grid(columns: (#{(['1fr'] * ans_cols(scale, form)).join(', ')}), column-gutter: 3mm,
          row-gutter: #{ans_row_gap(scale)}pt,
  TYP

  ln = ans_left_count(num, scale, form)
  sets.each_with_index do |s, i|
    out << %{  ansblock("#{t(:set_no, n: i + 1)}", #{typ_answers(s)}, #{ln}),\n}
  end
  out << ")\n"

  out
end

