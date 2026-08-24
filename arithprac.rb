# frozen_string_literal: true

# arithprac — 算数の計算問題・解答ジェネレータ
#
# 動作要件: Ruby 4.0 以降（標準ライブラリのみ）
# 出力     : Typst ファイル(.typ)を生成し、typst でコンパイルして PDF を得る
#
# 生成物:
#   - 問題 : A4 横(landscape)を中央で 2 分割して A5×2。1 枚(A5)に 1 回分。
#            1 ページ = 2 回分。--pages で回数を制御(回数 = 2 * pages)。
#            中央に切り取り線を入れる。左に前半・右に後半を並べる
#            (奇数個なら左が 1 つ多い)。
#   - 解答 : A4 縦。全回分をまとめて印刷(切らない)。「第N回」で対応付ける。
#
# 出題の指定:
#   --stage   : ステージ(パターンの混合比率と問題数のプリセット)
#   --pattern : パターン(単問の形式)を直接指定。--ratio で混合比率を指定。
#   いずれも指定が無い場合はエラー。

require 'optparse'

# ---- 設定 --------------------------------------------------------------
SETS             = 10  # 回数(A5 の枚数)の既定値。実際は 2 * pages。
DEFAULT_PAGES    = 10  # 問題ページ数の既定値(1 ページ = 2 回分 → 既定 20 回分)
DEFAULT_PROBLEMS = 20  # 1 回あたりの問題数の既定値(--pattern 使用時)
MIN_PROBLEMS     = 2   # 1 回あたりの問題数の下限
MAX_PROBLEMS     = 26  # 1 回あたりの問題数の上限
JP_FONT          = 'BIZ UDGothic'
BASENAME         = 'arithprac'

# 演算子記号(表示用)
OP_SYM = { add: '+', mul: '×' }.freeze

# スケール(文字・解答欄サイズ)。値は pt / mm(単位はテンプレート側で付与)。
#   inset_y : 問題行の行間(y)         valfs : 数値・等号のフォント
#   opfs    : 演算子(+/×)のフォント   boxw/boxh : 解答欄の幅・高さ
SCALES = {
  small:  { inset_y: 6,  valfs: 13, opfs: 12, boxw: 24, boxh: 8 },
  medium: { inset_y: 9,  valfs: 14, opfs: 13, boxw: 28, boxh: 12 },
  large:  { inset_y: 12, valfs: 16, opfs: 15, boxw: 28, boxh: 16 }
}.freeze
DEFAULT_SCALE = :small

# ---- パターン定義 ------------------------------------------------------
# 各パターンは op(:add/:mul)と、[a, b] を返す生成 proc を持つ。
# 制約(桁範囲・繰り上がり・0/1 の出現など)は棄却サンプリングで満たす。
PATTERNS = {}

def def_pattern(id, op, &gen)
  PATTERNS[id.upcase] = { id: id, op: op, gen: gen }
end

def no_zero?(n)
  !n.to_s.include?('0')
end

# --- 暗算-加算(P1-1-x)---
def_pattern('P1-1-1', :add) { [rand(1..5), rand(1..5)] } # 和 2..10
def_pattern('P1-1-2', :add) do                            # 6..9 + 1..5, 和 7..10
  loop { a = rand(6..9); b = rand(1..5); break [a, b] if a + b <= 10 }
end
def_pattern('P1-1-3', :add) do                            # 1..9 + 1..9, 和 2..10(繰上がり無)
  loop { a = rand(1..9); b = rand(1..9); break [a, b] if a + b <= 10 }
end
def_pattern('P1-1-4', :add) do                            # 6..9 + 2..5, 和 11..14
  loop { a = rand(6..9); b = rand(2..5); break [a, b] if a + b >= 11 }
end
def_pattern('P1-1-5', :add) { [rand(6..9), rand(5..9)] }  # 和 11..18
def_pattern('P1-1-6', :add) do                            # 2..9 + 2..9, 和 11..18(繰上がり有)
  loop { a = rand(2..9); b = rand(2..9); break [a, b] if a + b >= 11 }
end

# --- 暗算-乗算(P1-3-x)---
def_pattern('P1-3-1', :mul) { [rand(2..9), rand(2..9)] }
def_pattern('P1-3-2', :mul) { [rand(11..99), rand(2..9)] }
def_pattern('P1-3-3', :mul) { [rand(11..19), rand(11..19)] }
def_pattern('P1-3-4', :mul) do
  # 22..99 × 12..19。0 は出現しない。被乗数(a)に '1' は出現しない。
  loop do
    a = rand(22..99); b = rand(12..19)
    break [a, b] if no_zero?(a) && no_zero?(b) && !a.to_s.include?('1')
  end
end
def_pattern('P1-3-5', :mul) do
  # 12..99 × 12..99。0 は出現しない。4 桁のうち '1' が過不足なく 1 回。
  loop do
    a = rand(12..99); b = rand(12..99)
    s = "#{a}#{b}"
    break [a, b] if !s.include?('0') && s.count('1') == 1
  end
end
def_pattern('P1-3-6', :mul) do
  # 22..99 × 22..99。0 および 1 は出現しない。
  loop do
    a = rand(22..99); b = rand(22..99)
    s = "#{a}#{b}"
    break [a, b] if !s.include?('0') && !s.include?('1')
  end
end

# ---- ステージ定義 ------------------------------------------------------
# entries: [[パターン候補配列, 問題数], ...]。候補が複数なら等確率で 1 つ選ぶ。
# special: :kuku のステージは問題数・並び順・回数が固定(CLI 指定を無視)。
STAGES = {
  'S1-1-1' => { subtitle: 'たしざん暗算1', scale: :large, max_ones: 2, entries: [[%w[P1-1-1], 10]] },
  'S1-1-2' => { subtitle: 'たしざん暗算2', scale: :large, max_ones: 1,
                entries: [[%w[P1-1-1], 2], [%w[P1-1-2], 2], [%w[P1-1-3], 6]] },
  'S1-1-3' => { subtitle: 'たしざん暗算3', scale: :large, max_ones: 1,
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 8]] },
  'S1-1-4' => { subtitle: 'たしざん暗算4', scale: :large,
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 3], [%w[P1-1-5], 5]] },
  'S1-1-5' => { subtitle: 'たしざん暗算5', scale: :large,
                entries: [[%w[P1-1-3], 2], [%w[P1-1-6], 8]] },
  'S1-3-1' => { subtitle: 'かけざん暗算1', scale: :medium, special: :kuku },
  'S1-3-2' => { subtitle: 'かけざん暗算2', scale: :medium, entries: [[%w[P1-3-1], 20]] },
  'S1-3-3' => { subtitle: 'かけざん暗算3', scale: :medium, entries: [[%w[P1-3-2], 20]] },
  'S1-3-4' => { subtitle: 'かけざん暗算4', scale: :small, entries: [[%w[P1-3-3], 20]] },
  'S1-3-5' => { subtitle: 'かけざん暗算5', scale: :small, entries: [[%w[P1-3-4], 20]] },
  'S1-3-6' => { subtitle: 'かけざん暗算6', scale: :small, entries: [[%w[P1-3-5], 10], [%w[P1-3-6], 10]] }
}.freeze

def stage_num(stage)
  stage[:entries].sum { |_pats, count| count }
end

# ---- 問題生成 ----------------------------------------------------------

# 同一問題の重複回避で 1 問あたり試行する最大回数。
# これを超えたら(候補が枯渇しているため)重複を許容する。
UNIQUE_ATTEMPTS = 500

# パターン ID から 1 問生成。{a:, b:, op:, ans:, pid:} を返す。
# pid は差し替え時に同一パターンで再生成するために保持する。
def gen_problem(pid)
  pat = PATTERNS[pid.upcase]
  a, b = pat[:gen].call
  op = pat[:op]
  { a: a, b: b, op: op, ans: (op == :add ? a + b : a * b), pid: pat[:id] }
end

# 被演算数(a, b)に含まれる数字 '1' の個数。
def ones_in(prob)
  prob[:a].to_s.count('1') + prob[:b].to_s.count('1')
end

# 同一の問題(a, b, op が一致)が seen に無いものを生成して返す。
# pats が複数なら毎回等確率でパターンを選び直す。候補枯渇時は重複を許容。
#   seen : 同一回内で既出の問題キーを記録するハッシュ(呼び出し側で用意)
def gen_unique(pats, seen)
  UNIQUE_ATTEMPTS.times do
    p = gen_problem(pats.sample)
    key = [p[:a], p[:b], p[:op]]
    next if seen[key]

    seen[key] = true
    return p
  end
  gen_problem(pats.sample) # 最終手段: 重複を許容
end

# 問題配列に通し番号を付与する。
def numbered(probs)
  probs.each_with_index.map { |p, i| p.merge(n: i + 1) }
end

# 同一パターン(pid)で '1' を含まない問題を、可能な限り重複せず生成する。
def gen_no_one(pid, seen)
  UNIQUE_ATTEMPTS.times do
    p = gen_problem(pid)
    next unless ones_in(p).zero?

    key = [p[:a], p[:b], p[:op]]
    next if seen[key]

    seen[key] = true
    return p
  end
  # 重複回避を諦めても '1' 無しは優先する
  UNIQUE_ATTEMPTS.times do
    p = gen_problem(pid)
    return p if ones_in(p).zero?
  end
  gen_problem(pid) # 最終手段
end

# 1 回内で被演算数に現れる '1' の総数を max_ones 以下に調整する。
# '1' を含む問題を問題番号(n)の大きい順に、'1' を含まない同一パターン問題へ
# 差し替える。差し替え後の問題は '1' を含まないので、繰り返すと総数は必ず減る。
def adjust_ones!(set, max_ones, seen)
  loop do
    break if set.sum { |p| ones_in(p) } <= max_ones

    target = set.select { |p| ones_in(p).positive? }.max_by { |p| p[:n] }
    break unless target

    seen.delete([target[:a], target[:b], target[:op]])
    repl = gen_no_one(target[:pid], seen).merge(n: target[:n])
    set[set.index { |p| p[:n] == target[:n] }] = repl
  end
  set
end

# 前半(左側)に並べる問題数。半分(奇数なら切り上げ)。
def left_count(num)
  (num + 1) / 2
end

# ステージ 1 回分を生成。同一回内で同一の問題は重複しない。
def make_stage_set(stage)
  seen = {}
  probs = []
  stage[:entries].each do |pats, count|
    count.times { probs << gen_unique(pats, seen) }
  end
  set = numbered(probs.shuffle)
  adjust_ones!(set, stage[:max_ones], seen) if stage[:max_ones]
  set
end

# 九九ステージ(S1-3-1)の全回分を生成。並び順固定・シャッフルしない。
#   各回: 左に段 r(r×2..r×9)、右に段 r+1。回数は 4 で固定。
def make_kuku_sets
  [[2, 3], [4, 5], [6, 7], [8, 9]].map do |lr, rr|
    left  = (2..9).map { |b| { a: lr, b: b, op: :mul, ans: lr * b } }
    right = (2..9).map { |b| { a: rr, b: b, op: :mul, ans: rr * b } }
    numbered(left + right)
  end
end

# --ratio の比率(合計 1 の Rational 配列)を num 問へ丸め、各パターンの割当数を返す。
def allocate_counts(ratios, num)
  alloc = ratios.map { |r| (r * num).truncate }
  (num - alloc.sum).times do
    fracs = ratios.each_with_index.map { |r, i| r * num - alloc[i] }
    cand  = fracs.each_index.select { |i| fracs[i] > 0 }
    total = cand.sum { |i| fracs[i] }
    r = rand * total
    acc = 0r
    chosen = cand.last
    cand.each { |i| acc += fracs[i]; (chosen = i; break) if r < acc }
    alloc[chosen] += 1
  end
  alloc
end

# --pattern/--ratio 指定の 1 回分を生成。同一回内で同一の問題は重複しない。
def make_pattern_set(patterns, ratios, num)
  counts = allocate_counts(ratios, num)
  seen = {}
  probs = []
  patterns.each_with_index { |pid, i| counts[i].times { probs << gen_unique([pid], seen) } }
  numbered(probs.shuffle)
end

# 丸数字(①..⑳ / ㉑..㉟)を返す。
def circled(n)
  cp = n <= 20 ? 0x2460 + (n - 1) : 0x3251 + (n - 21)
  [cp].pack('U')
end

# ---- Typst 生成 --------------------------------------------------------

# 問題テーブルのセル配列(Typst の array of dict リテラル)。
def typ_problems(items)
  '(' + items.map { |p|
    %{(n: "#{circled(p[:n])}", a: #{p[:a]}, b: #{p[:b]}, op: "#{OP_SYM[p[:op]]}")}
  }.join(', ') + ',)'
end

# 解答テーブルのセル配列
def typ_answers(items)
  '(' + items.map { |p| %{(n: "#{circled(p[:n])}", p: #{p[:ans]})} }.join(', ') + ',)'
end

def build_typst(sets, num, title_text, stage_name = nil, scale = DEFAULT_SCALE)
  sets_count = sets.size
  ln = left_count(num)
  s = SCALES[scale]
  out = +''
  out << <<~TYP
    // 自動生成ファイル (arithprac.rb) — 直接編集しないでください。
    #set text(font: "#{JP_FONT}", size: 12pt, lang: "ja")

    // ステージ名(ステージ指定時のみ。空文字なら非表示)。「第N回」の左に置く。
    #let stagename = "#{stage_name}"

    // --- 寸法(スケール: #{scale}) ---
    #let boxw = #{s[:boxw]}mm   // 解答欄(横長の□)の幅
    #let boxh = #{s[:boxh]}mm    // 解答欄の高さ(手書き用に本文より少し大きめ)
    #let numw = 6mm    // 問題番号の欄幅
    #let valw = 10mm   // 被演算数・演算数の欄幅(3 桁でも右揃えで収まる)
    #let opw  = 5mm    // 演算子(+, ×, =)の欄幅
    #let valfs = #{s[:valfs]}pt  // 数値・等号のフォントサイズ
    #let opfs  = #{s[:opfs]}pt  // 演算子(+/×)のフォントサイズ

    #let ansbox = box(width: boxw, height: boxh, stroke: 0.7pt, radius: 1pt)
    #let ansfs = 10pt  // 解答の文字サイズ(人間が読みやすい固定サイズ)

    // 1 問分の行(6 セル)。数値は右揃えで右端をそろえる。
    #let probrow(n, a, b, op) = (
      align(right)[#text(size: 12pt)[#n]],
      align(right)[#text(size: valfs)[#(str(a))]],
      align(center)[#text(size: opfs)[#op]],
      align(right)[#text(size: valfs)[#(str(b))]],
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
      #align(center)[#text(size: 18pt, weight: "bold")[#{title_text}]]
      #v(3pt)
      #align(center)[#text(size: 10pt)[
        #if stagename != "" [#stagename #h(6mm)]#title #h(8mm) 名前 #box(width: 28mm, stroke: (bottom: 0.5pt))[] #h(4mm) 得点 #box(width: 14mm, stroke: (bottom: 0.5pt))[]
      ]]
      #v(8pt)
      // 左(前半)と右(後半)を区切る点線。線をやや左に寄せ、右列の番号との隙間を広めに。
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

    // 解答 1 問分(番号・答えの 2 セル)。番号は左揃え、答えは右揃え。
    // これにより「枠左線↔番号」「点線↔右番号」「右答え↔枠右線」の隙間が
    // すべて等しく(#anspad + セル内側 2pt)なる。
    #let anscell(it) = (
      align(left)[#text(size: ansfs)[#it.n]],
      align(right)[#text(size: ansfs)[#(str(it.p))]],
    )

    // 解答セルの列幅(4 回分を横に並べるため詰めている)。
    #let ansnumw = 6mm   // 番号(丸数字)の欄幅
    #let answ    = 12mm  // 答えの欄幅(最大 4 桁 9801 でも右揃えで収まる)

    // 解答の 1 列。番号(左揃え)・答え(右揃え)。
    #let ansminicol(items) = table(
      columns: (ansnumw, answ), stroke: none, inset: (x: 2pt, y: 1pt),
      ..items.map(it => anscell(it)).flatten())

    // 枠線・点線と数字の共通すき間。左右の外側と中央の点線まわりで同じ幅にする。
    #let anspad = 2mm

    // 解答 1 ブロック(第N回)。問題と同様に 前半 / 後半 の縦 2 列で表示。
    // ブロック幅は内容に合わせて縮める(右側の余白を作らない)。
    #let ansblock(title, items, leftn) = block(inset: (x: anspad, y: 6pt), radius: 2pt,
      stroke: 0.5pt, breakable: false, [
        #text(weight: "bold", size: 11pt)[#title]
        #v(3pt)
        #grid(columns: (auto, anspad, anspad, auto), align: top,
          grid.vline(x: 2, stroke: (paint: luma(140), thickness: 0.6pt, dash: "dotted")),
          ansminicol(items.slice(0, leftn)), [], [], ansminicol(items.slice(leftn)))
      ])

    // ================= 問題(A4 横) =================
    #set page(paper: "a4", flipped: true, margin: (x: 6mm, y: 8mm))
  TYP

  # 問題ページ(2 回分ずつ)。前半 ln 問を左、残りを右に並べる。
  (0...sets_count).step(2) do |i|
    a = sets[i]
    b = sets[i + 1]
    la = typ_problems(a[0...ln])
    ra = typ_problems(a[ln...num])
    lb = typ_problems(b[0...ln])
    rb = typ_problems(b[ln...num])
    out << %{\n#sheetpair(\n  probset("第#{i + 1}回", #{la}, #{ra}),\n  probset("第#{i + 2}回", #{lb}, #{rb}),\n)\n}
    out << "#pagebreak()\n" if i + 2 < sets_count
  end

  # ================= 解答(A4 縦) =================
  out << <<~TYP

    #set page(flipped: false, margin: (x: 10mm, y: 10mm))
    #align(center)[#text(size: 16pt, weight: "bold")[#{title_text}#if stagename != "" [ #stagename] 解答]]
    #v(6pt)
    #grid(columns: (1fr, 1fr, 1fr, 1fr), column-gutter: 3mm, row-gutter: 6pt,
  TYP

  sets.each_with_index do |s, i|
    out << %{  ansblock("第#{i + 1}回", #{typ_answers(s)}, #{ln}),\n}
  end
  out << ")\n"

  out
end

# ---- メイン ------------------------------------------------------------

main = lambda do
options = { pages: DEFAULT_PAGES, num: DEFAULT_PROBLEMS, seed: nil,
            stage: nil, patterns: [], ratios: [], output: nil, stage_list: false,
            scale: nil }

OptionParser.accept(Rational) do |s,|
  Rational(s)
rescue ArgumentError, ZeroDivisionError, TypeError
  raise OptionParser::InvalidArgument, s
end

parser = OptionParser.new do |o|
  o.banner = '使い方: ruby arithprac.rb [options]'
  o.on('-s S', '--stage S', String, 'ステージ名(例: S1-1-1)。--num/--pattern/--ratio を無視。') { |v| options[:stage] = v }
  o.on('-p P', '--pages P', Integer, "問題のページ数(1 ページ = 2 回分, 既定 #{DEFAULT_PAGES})") { |v| options[:pages] = v }
  o.on('--stage-list', 'ステージ名とサブタイトルの一覧を表示して終了') { options[:stage_list] = true }
  o.on('--num N', Integer, "1 回あたりの問題数 (#{MIN_PROBLEMS}〜#{MAX_PROBLEMS}, 既定 #{DEFAULT_PROBLEMS})") { |v| options[:num] = v }
  o.on('--pattern P', String, 'パターン名(例: P1-1-1)。複数指定可。--stage を無視。') { |v| options[:patterns] << v }
  o.on('--ratio R', Rational, 'パターンの混合比率(--pattern と同数)。合計 1 に正規化。') { |v| options[:ratios] << v }
  o.on('--scale S', String, '文字・解答欄サイズ small/medium/large(既定 small)。--stage 指定時は無視。') { |v| options[:scale] = v }
  o.on('-o O', '--output O', String, "出力ファイル名(.pdf)。不正な拡張子なら #{BASENAME}.pdf を使用。") { |v| options[:output] = v }
  o.on('--seed S', Integer, '乱数シード(再現用)') { |v| options[:seed] = v }
  o.on('-h', '--help', 'この使い方を表示') { puts o; exit }
end
parser.parse!(ARGV)

# --stage-list: 一覧表示して終了
if options[:stage_list]
  STAGES.each { |id, s| puts "#{id}\t#{s[:subtitle]}" }
  exit
end

if options[:seed]
  srand(options[:seed])
  puts "seed = #{options[:seed]} で生成します。"
else
  puts '乱数 seed 指定なし(毎回異なる問題)。'
end

pages = options[:pages]
abort "エラー: --pages は 1 以上を指定してください(指定: #{pages})。" if pages < 1
sets_count = 2 * pages

# --scale の検証(指定された場合のみ)。実際に採用するスケールはモード決定時に確定。
scale_opt = nil
if options[:scale]
  scale_opt = options[:scale].downcase.to_sym
  unless SCALES.key?(scale_opt)
    abort "エラー: --scale は small/medium/large のいずれかを指定してください(指定: #{options[:scale]})。"
  end
end

# 出題モードの決定: --stage 優先、無ければ --pattern、いずれも無ければエラー。
title_text = '暗算マスター'
stage_name = nil  # ステージ指定時のみサブタイトルを「第N回」の左に表示する
scale = DEFAULT_SCALE

if options[:stage]
  key = options[:stage].upcase
  stage = STAGES[key]
  abort "エラー: ステージ '#{options[:stage]}' は存在しません(一覧は --stage-list)。" unless stage
  warn '警告: --stage 指定時は --pattern/--ratio/--num は無視されます。' if !options[:patterns].empty? || !options[:ratios].empty?
  warn '警告: --stage 指定時は --scale は無視されます(ステージ固有のスケールを使用)。' if scale_opt
  stage_name = stage[:subtitle]
  scale = stage[:scale] # ステージ指定時は --scale を無視しステージ固有スケールを使う

  if stage[:special] == :kuku
    # 九九: 問題数・並び順・回数(4)が固定。--pages も無視。
    sets = make_kuku_sets
    num = 16
    puts "ステージ #{key}(#{stage[:subtitle]}): 九九固定 4 回・1 回 16 問(scale=#{scale}, CLI 指定は無視)。"
  else
    num = stage_num(stage)
    sets = Array.new(sets_count) { make_stage_set(stage) }
    puts "ステージ #{key}(#{stage[:subtitle]}): #{sets_count} 回・1 回 #{num} 問(scale=#{scale})。"
  end

elsif !options[:patterns].empty?
  patterns = options[:patterns]
  unknown = patterns.reject { |p| PATTERNS.key?(p.upcase) }
  abort "エラー: パターンが存在しません: #{unknown.join(', ')}" unless unknown.empty?

  num = options[:num]
  unless (MIN_PROBLEMS..MAX_PROBLEMS).include?(num)
    abort "エラー: 問題数は #{MIN_PROBLEMS}〜#{MAX_PROBLEMS} の範囲で指定してください(指定: #{num})。"
  end

  ratios = options[:ratios]
  if ratios.empty?
    ratios = Array.new(patterns.size, Rational(1, patterns.size))
  else
    abort 'エラー: --ratio は --pattern と同じ数だけ指定してください。' unless ratios.size == patterns.size
    abort 'エラー: --ratio に負の値は指定できません。' if ratios.any?(&:negative?)
    total = ratios.sum(0r)
    abort 'エラー: --ratio の合計が 0 です。' if total.zero?
    ratios = ratios.map { |r| r / total }
  end

  scale = scale_opt || DEFAULT_SCALE
  sets = Array.new(sets_count) { make_pattern_set(patterns, ratios, num) }
  puts "パターン #{patterns.join(', ')}: #{sets_count} 回・1 回 #{num} 問(scale=#{scale})。"

else
  warn 'エラー: --stage または --pattern を指定してください(一覧は --stage-list)。'
  warn parser.help
  exit 1
end

# 出力先の決定
pdf_path = if options[:output]&.downcase&.end_with?('.pdf')
             options[:output]
           else
             warn "警告: 出力拡張子が .pdf ではないため #{BASENAME}.pdf を使用します。" if options[:output]
             "#{BASENAME}.pdf"
           end
typ_path = pdf_path.sub(/\.pdf\z/i, '.typ')

File.write(typ_path, build_typst(sets, num, title_text, stage_name, scale))
puts "Typst ファイルを生成: #{typ_path}"

if system('typst', 'compile', typ_path, pdf_path)
  pages_out = begin
    `pdfinfo #{pdf_path} 2>/dev/null`[/Pages:\s*(\d+)/, 1]
  rescue StandardError
    nil
  end
  puts "PDF を生成: #{pdf_path}#{pages_out ? " (全#{pages_out}ページ)" : ''}"
else
  warn 'typst のコンパイルに失敗しました。上の出力を確認してください。'
  exit 1
end
end

main.call if __FILE__ == $PROGRAM_NAME
