# frozen_string_literal: true

# 暗算マスター — かけ算 暗算問題・解答ジェネレータ
#
# 動作要件: Ruby 3.4 以降（WSL の 4.0.6 で確認）
# 出力     : Typst ファイル(.typ)を生成し、typst でコンパイルして PDF を得る
#
# 生成物:
#   - 問題 : A4 横(landscape)を中央で 2 分割して A5×2。1 枚(A5)に 1 回分。
#            10 回分 = A5 10 枚 = A4 5 ページ。中央に切り取り線を入れる。
#            左に前半・右に後半を並べる(奇数個なら左が 1 つ多い)。
#   - 解答 : A4 縦。10 回分をまとめて印刷(切らない)。
#            どの回の解答かが分かるよう「第N回」で対応付ける。
#
# 使い方:
#   ruby arithprac.rb [-n 問題数] [-s シード]
#     -n, --num N  : 1 回あたりの問題数 (2〜26, 既定 20)
#     -s, --seed S : 乱数シード(再現用)

require 'optparse'

# ---- 設定 --------------------------------------------------------------
SETS             = 10  # 回数(A5 の枚数)
DEFAULT_PROBLEMS = 20  # 1 回あたりの問題数の既定値
MIN_PROBLEMS     = 2   # 1 回あたりの問題数の下限
MAX_PROBLEMS     = 26  # 1 回あたりの問題数の上限
JP_FONT          = 'BIZ UDGothic'
BASENAME         = 'arithprac'

# 桁数設定。将来 3 桁×3 桁 まで拡張できるよう桁数で管理する。
DIGITS_MULTIPLICAND = 2 # 被乗数の桁数
DIGITS_MULTIPLIER   = 2 # 乗数の桁数
# ----------------------------------------------------------------------

# 指定桁数の数値をランダム生成する。
#   digits    : 桁数
#   allow_one : 各桁に 1 を許可するか
#   force_one_at : 指定した位置(0=最上位)を必ず 1 にする(nil で無し)
# いずれの桁にも 0 は入れない(0 が来ると暗算が簡単になりすぎるため)。
def rand_number(digits, allow_one:, force_one_at: nil)
  ds = Array.new(digits) do |i|
    if force_one_at == i
      1
    else
      loop do
        d = rand(1..9)
        break d if allow_one || d != 1
      end
    end
  end
  ds.reduce(0) { |acc, d| acc * 10 + d }
end

# 「1」をどこにも含まない問題を作る。
def make_no_one
  a = rand_number(DIGITS_MULTIPLICAND, allow_one: false)
  b = rand_number(DIGITS_MULTIPLIER,   allow_one: false)
  { a: a, b: b }
end

# 4 桁(被乗数2桁 + 乗数2桁 = 一般に全桁)のうち 1 か所だけを「1」にする問題を作る。
def make_with_one
  total = DIGITS_MULTIPLICAND + DIGITS_MULTIPLIER
  pos = rand(total) # 0..(total-1) 通し位置
  if pos < DIGITS_MULTIPLICAND
    a = rand_number(DIGITS_MULTIPLICAND, allow_one: false, force_one_at: pos)
    b = rand_number(DIGITS_MULTIPLIER,   allow_one: false)
  else
    a = rand_number(DIGITS_MULTIPLICAND, allow_one: false)
    b = rand_number(DIGITS_MULTIPLIER,   allow_one: false, force_one_at: pos - DIGITS_MULTIPLICAND)
  end
  { a: a, b: b }
end

# 「1」入り問題数を返す。指定問題数の半分(奇数なら切り上げ)。
#   例: 20 → 10、25 → 13
def with_one_count(num)
  (num + 1) / 2
end

# 前半(左側)に並べる問題数を返す。半分(奇数なら切り上げ)。
#   例: 20 → 10、25 → 13(右は 12)
def left_count(num)
  (num + 1) / 2
end

# 1 回分(num 問)を生成。半分(切り上げ)は「1」入り、残りは「1」無し。位置はシャッフル。
def make_set(num)
  w = with_one_count(num)
  probs = []
  w.times          { probs << make_with_one }
  (num - w).times  { probs << make_no_one }
  probs.shuffle!
  probs.each_with_index.map { |p, i| { n: i + 1, a: p[:a], b: p[:b] } }
end

# ---- Typst 生成 --------------------------------------------------------

# 問題テーブルのセル配列(Typst の array of dict リテラル)。
# 末尾にカンマを付け、要素が 1 個でも「配列」として解釈させる。
def typ_problems(items)
  '(' + items.map { |p| "(n: #{p[:n]}, a: #{p[:a]}, b: #{p[:b]})" }.join(', ') + ',)'
end

# 解答テーブルのセル配列
def typ_answers(items)
  '(' + items.map { |p| "(n: #{p[:n]}, p: #{p[:a] * p[:b]})" }.join(', ') + ',)'
end

def build_typst(sets, num)
  ln = left_count(num)
  out = +''
  out << <<~TYP
    // 自動生成ファイル (arithprac.rb) — 直接編集しないでください。
    #set text(font: "#{JP_FONT}", size: 12pt, lang: "ja")

    // --- 寸法(将来 3 桁×3 桁 でも数値右揃え・解答欄の位置と大きさをそろえる) ---
    #let boxw = 24mm   // 解答欄(横長の□)の幅
    #let boxh = 8mm    // 解答欄の高さ(手書き用に本文より少し大きめ)
    #let numw = 6mm    // 問題番号の欄幅
    #let valw = 10mm   // 被乗数・乗数の欄幅(3 桁でも右揃えで収まる)
    #let opw  = 5mm    // 演算子(×, =)の欄幅

    #let ansbox = box(width: boxw, height: boxh, stroke: 0.7pt, radius: 1pt)
    #let ansfs = 9pt   // 解答の文字サイズ(人間が読みやすい固定サイズ)

    // 1 問分の行(6 セル)。数値は右揃えで右端をそろえる。
    #let probrow(n, a, b) = (
      align(right)[#text(size: 12pt)[#(str(n) + ".")]],
      align(right)[#text(size: 13pt)[#(str(a))]],
      align(center)[#text(size: 12pt)[×]],
      align(right)[#text(size: 13pt)[#(str(b))]],
      align(center)[#text(size: 12pt)[=]],
      align(left + horizon)[#ansbox],
    )

    #let probtable(items) = table(
      columns: (numw, valw, opw, valw, opw, auto),
      stroke: none,
      align: horizon,
      inset: (x: 2pt, y: 6pt),
      ..items.map(it => probrow(it.n, it.a, it.b)).flatten()
    )

    // A5 1 枚分(1 回分)。左に前半、右に後半を並べる。
    #let probset(title, left, right) = block(width: 100%, height: 100%, [
      #align(center)[#text(size: 18pt, weight: "bold")[暗算マスター]]
      #v(3pt)
      #align(center)[#text(size: 10pt)[
        #title #h(8mm) 名前 #box(width: 28mm, stroke: (bottom: 0.5pt))[] #h(4mm) 得点 #box(width: 14mm, stroke: (bottom: 0.5pt))[]
      ]]
      #v(8pt)
      // 左(前半)と右(後半)を区切る点線。線をやや左に寄せ、
      // 右列の問題番号との隙間を広めにとる(左 1.5mm / 右 6mm)。
      #grid(columns: (1fr, 1.5mm, 6mm, 1fr), align: top,
        grid.vline(x: 2, stroke: (paint: luma(140), thickness: 0.6pt, dash: "dotted")),
        probtable(left), [], [], probtable(right))
    ])

    // 中央の切り取り線(A4 横を A5×2 に分けるための目印)
    #let cutline = place(top + center,
      rect(width: 0pt, height: 100%,
        stroke: (left: (paint: luma(150), thickness: 0.6pt, dash: "dashed"))))

    // A4 横 1 ページ = A5 2 枚(2 回分)
    #let sheetpair(setA, setB) = {
      grid(columns: (1fr, 1fr), column-gutter: 10mm, setA, setB)
      cutline
    }

    // 解答 1 問分(番号・積の 2 セル)。ともに右揃えで縦位置をそろえる。
    #let anscell(it) = (
      align(right)[#text(size: ansfs)[#(str(it.n) + ".")]],
      align(right)[#text(size: ansfs)[#(str(it.p))]],
    )

    // 解答の 1 列。番号・積を右揃えでそろえる。
    #let ansminicol(items) = table(
      columns: (7mm, 14mm), stroke: none, inset: (x: 2pt, y: 1pt),
      ..items.map(it => anscell(it)).flatten())

    // 解答 1 ブロック(第N回)。問題と同様に 前半 / 後半 の縦 2 列で表示。
    // leftn = 左列に並べる問題数。線をやや左に寄せ、右列との隙間を広めにとる。
    #let ansblock(title, items, leftn) = block(width: 100%, inset: 6pt, radius: 2pt,
      stroke: 0.5pt, breakable: false, [
        #text(weight: "bold", size: 11pt)[#title]
        #v(3pt)
        #grid(columns: (auto, 1.5mm, 6mm, auto), align: top,
          grid.vline(x: 2, stroke: (paint: luma(140), thickness: 0.6pt, dash: "dotted")),
          ansminicol(items.slice(0, leftn)), [], [], ansminicol(items.slice(leftn)))
      ])

    // ================= 問題(A4 横 × 5 ページ) =================
    #set page(paper: "a4", flipped: true, margin: (x: 6mm, y: 8mm))
  TYP

  # 問題ページ(2 回分ずつ)。前半 ln 問を左、残りを右に並べる。
  (0...SETS).step(2) do |i|
    a = sets[i]
    b = sets[i + 1]
    la = typ_problems(a[0...ln])
    ra = typ_problems(a[ln...num])
    lb = typ_problems(b[0...ln])
    rb = typ_problems(b[ln...num])
    out << %{\n#sheetpair(\n  probset("第#{i + 1}回", #{la}, #{ra}),\n  probset("第#{i + 2}回", #{lb}, #{rb}),\n)\n}
    out << "#pagebreak()\n" if i + 2 < SETS
  end

  # ================= 解答(A4 縦 × 1 ページ) =================
  # set page 規則はここで自動的に改ページし、縦向きの新しいページを始める。
  out << <<~TYP

    #set page(flipped: false, margin: (x: 10mm, y: 10mm))
    #align(center)[#text(size: 16pt, weight: "bold")[暗算マスター 解答]]
    #v(6pt)
    // 「第N回」の囲みを横 3 列に並べる(2 列より 1 ブロックの高さに余裕が出る)。
    #grid(columns: (1fr, 1fr, 1fr), column-gutter: 5mm, row-gutter: 6pt,
  TYP

  sets.each_with_index do |s, i|
    out << %{  ansblock("第#{i + 1}回", #{typ_answers(s)}, #{ln}),\n}
  end
  out << ")\n"

  out
end

# ---- メイン ------------------------------------------------------------

options = { num: DEFAULT_PROBLEMS, seed: nil }
parser = OptionParser.new do |o|
  o.banner = '使い方: ruby arithprac.rb [options]'
  o.on('-n', '--num N', Integer,
       "1 回あたりの問題数 (#{MIN_PROBLEMS}〜#{MAX_PROBLEMS}, 既定 #{DEFAULT_PROBLEMS})") { |v| options[:num] = v }
  o.on('-s', '--seed S', Integer, '乱数シード(再現用)') { |v| options[:seed] = v }
  o.on('-h', '--help', 'この使い方を表示') { puts o; exit }
end
parser.parse!(ARGV)

# 後方互換: 余った位置引数(数値)はシードとして扱う。
options[:seed] ||= Integer(ARGV[0], exception: false) if ARGV[0]

num = options[:num]
unless (MIN_PROBLEMS..MAX_PROBLEMS).include?(num)
  abort "エラー: 問題数は #{MIN_PROBLEMS}〜#{MAX_PROBLEMS} の範囲で指定してください(指定: #{num})。"
end

if options[:seed]
  srand(options[:seed])
  puts "seed = #{options[:seed]} で生成します。"
else
  puts '乱数 seed 指定なし(毎回異なる問題)。'
end

w = with_one_count(num)
puts "1 回あたり #{num} 問(うち「1」入り #{w} 問 / 「1」無し #{num - w} 問)、左 #{left_count(num)} 問 / 右 #{num - left_count(num)} 問。"

sets = Array.new(SETS) { make_set(num) }

typ_path = File.join(__dir__, "#{BASENAME}.typ")
pdf_path = File.join(__dir__, "#{BASENAME}.pdf")

File.write(typ_path, build_typst(sets, num))
puts "Typst ファイルを生成: #{typ_path}"

# typst でコンパイル
if system('typst', 'compile', typ_path, pdf_path)
  pages = `pdfinfo #{pdf_path} 2>/dev/null`[/Pages:\s*(\d+)/, 1] rescue nil
  puts "PDF を生成: #{pdf_path}#{pages ? " (全#{pages}ページ)" : ''}"
else
  warn 'typst のコンパイルに失敗しました。上の出力を確認してください。'
  exit 1
end
