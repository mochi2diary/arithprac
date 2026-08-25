# frozen_string_literal: true

# arithprac — 算数の計算問題・解答ジェネレータ
#
# 動作要件: Ruby 4.0 以降（標準ライブラリのみ）
# 出力     : Typst ファイル(.typ)を生成し、typst でコンパイルして PDF を得る
#
# 出題形式:
#   - 暗算(P1-x-x): 式を 1 行に並べ、右端の□に答えを書かせる。
#   - 筆算(P2-x-x): 1 回分の領域をリージョンに等分割し、1 問ずつ筆算の形で置く。
#
# 生成物:
#   - 問題 : A4 横(landscape)を中央で 2 分割して A5×2。1 枚(A5)に 1 回分。
#            1 ページ = 2 回分。--pages で回数を制御(回数 = 2 * pages)。
#            中央に切り取り線を入れる。
#            暗算は左に前半・右に後半を並べる(奇数個なら左が 1 つ多い)。
#            筆算は 1 回分を --num 個のリージョンに分けて行優先に並べる。
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
DEFAULT_REGIONS  = 6   # 筆算の 1 回あたりの問題数(= リージョン数)の既定値
JP_FONT          = 'BIZ UDGothic'
# 筆算の数字・演算子だけに使うフォント(本文の JP_FONT とは独立に選ぶ)。
COLUMN_DIGIT_FONT = 'BIZ UDGothic'
BASENAME         = 'arithprac'

# 筆算のリージョン分割形 { 問題数(= リージョン数) => [縦の個数(行), 横の個数(列)] }
REGION_SHAPES = { 12 => [4, 3], 8 => [4, 2], 6 => [3, 2], 4 => [2, 2], 1 => [1, 1] }.freeze

# ページ下端のタグ(シード下位 16bit の 16 進 4 文字)。印刷後に問題と解答を対応づける。
# 問題(A4 横)は切り離した A5 の左下それぞれに、解答(A4 縦)は左下 1 箇所に入れる。
TAG_MARGIN = 5      # 用紙の左端・下端からの距離(mm)。プリンタの印字限界に近い位置。
TAG_FS     = 6      # タグの文字サイズ(pt)
TAG_LUMA   = 120    # タグの文字色(luma。小さいほど濃い)
A5_WIDTH   = 148.5  # A4 横を 2 分割した A5 1 枚の幅(mm)

# 見出し(回・名前・得点)と問題本体の間の空き(pt)。出題形式ごとに異なる。
HEAD_GAP = { mental: 8, column: 12 }.freeze

# 演算子記号(表示用)。筆算は全角を使う(半角より字形が広く、字間が行間と釣り合う)。
OP_SYM     = { add: '+', sub: '−', mul: '×' }.freeze
OP_SYM_ZEN = { add: '＋', sub: '－', mul: '×' }.freeze

# スケール(文字・解答欄サイズ)。値は pt / mm(単位はテンプレート側で付与)。
#   inset_y : 問題行の行間(y)         valfs : 数値・等号のフォント
#   opfs    : 演算子(+/×)のフォント   boxw/boxh : 解答欄の幅・高さ
SCALES = {
  small:  { inset_y: 6,  valfs: 13, opfs: 12, boxw: 24, boxh: 8 },
  medium: { inset_y: 9,  valfs: 14, opfs: 13, boxw: 28, boxh: 12 },
  large:  { inset_y: 12, valfs: 16, opfs: 15, boxw: 28, boxh: 16 }
}.freeze
DEFAULT_SCALE = :small

# 筆算のスケール。リージョン割り(--num)とは独立の設定。値は mm / pt。
#   digw    : 数字 1 桁分のセルの幅          digfs    : 数字のフォント
#   digh_a  : 被加数行の高さ                 digh_b   : 加数行の高さ
#   ruleh   : 横線行の高さ                   rulethk  : 横線の太さ
#   rpad_x  : リージョン内の左右の余白         rpad_top : 同・上の余白(繰り上がりを書く分)
# 解答記入行の高さは 1fr(リージョンの余りを吸収する)。
COLUMN_SCALES = {
  small:  { digw: 4.8, digh_a: 7.2,  digh_b: 6,   digfs: 14, ruleh: 0.5, rulethk: 0.6,
            rpad_x: 3.6, rpad_top: 6 },
  medium: { digw: 6,   digh_a: 9.6,  digh_b: 7.5, digfs: 16, ruleh: 0.5, rulethk: 0.7,
            rpad_x: 4,   rpad_top: 7 },
  large:  { digw: 6.9, digh_a: 10.8, digh_b: 9,   digfs: 18, ruleh: 0.5, rulethk: 0.8,
            rpad_x: 4.8, rpad_top: 8 }
}.freeze

# ---- パターン定義 ------------------------------------------------------
# 各パターンは op(:add/:sub/:mul)と、[a, b] を返す生成 proc を持つ。
# 制約(桁範囲・繰り上がり・0/1 の出現など)は棄却サンプリングで満たす。
# form は出題形式。P1-x-x は暗算(:mental)、P2-x-x は筆算(:column)。
PATTERNS = {}

def def_pattern(id, op, &gen)
  form = id.upcase.start_with?('P2') ? :column : :mental
  PATTERNS[id.upcase] = { id: id, op: op, form: form, gen: gen }
end

# パターン ID の出題形式(:mental / :column)。
def pattern_form(pid)
  PATTERNS[pid.upcase][:form]
end

# 数字を全角にする。筆算の問題部分のみで使う(解答ページは半角のまま)。
def zen_digits(n)
  n.to_s.tr('0-9', '０-９')
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

# --- 暗算-減算(P1-2-x)---
def_pattern('P1-2-1', :sub) do                            # 1..10 - 1..10, 差 0..9(a >= b)
  loop { a = rand(1..10); b = rand(1..10); break [a, b] if a >= b }
end
def_pattern('P1-2-2', :sub) do                            # 10..19 - 1..9, 差 1..10
  loop { a = rand(10..19); b = rand(1..9); break [a, b] if a - b <= 10 }
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

# --- 筆算-加算(P2-1-x)---
# 繰り上がりの有無は各位の和で判定する。「十の位への繰り上がり」= 一の位からの繰上げ、
# 「百の位への繰り上がり」= 十の位からの繰上げ、「千の位への繰り上がり」= 百の位から。
def_pattern('P2-1-1', :add) do   # 2桁 + 1桁 = 2桁(繰り上がりなし)
  loop { a = rand(10..99); b = rand(1..9); break [a, b] if a % 10 + b <= 9 }
end
def_pattern('P2-1-2', :add) do   # 2桁 + 1桁 = 2桁(十の位への繰り上がりあり)
  loop { a = rand(10..99); b = rand(1..9); break [a, b] if a % 10 + b >= 10 && a + b <= 99 }
end
def_pattern('P2-1-3', :add) do   # 2桁 + 2桁 = 2桁(繰り上がりなし)
  loop do
    a = rand(10..99); b = rand(10..99)
    break [a, b] if a % 10 + b % 10 <= 9 && a / 10 + b / 10 <= 9
  end
end
def_pattern('P2-1-4', :add) do   # 2桁 + 2桁 = 2桁(十の位への繰り上がりあり)
  loop do
    a = rand(10..99); b = rand(10..99)
    break [a, b] if a % 10 + b % 10 >= 10 && a + b <= 99
  end
end
def_pattern('P2-1-5', :add) do   # 2桁 + 2桁 = 3桁(百の位への繰り上がりあり)
  loop { a = rand(10..99); b = rand(10..99); break [a, b] if a + b >= 100 }
end
def_pattern('P2-1-6', :add) do   # 3桁 + 2桁 = 3桁(千の位への繰り上がりなし)
  loop { a = rand(100..999); b = rand(10..99); break [a, b] if a + b <= 999 }
end
def_pattern('P2-1-7', :add) do   # 3桁 + 2桁(千の位への繰り上がりあり → 結果 4桁)
  loop { a = rand(100..999); b = rand(10..99); break [a, b] if a + b >= 1000 }
end
def_pattern('P2-1-8', :add) do   # 3桁 + 3桁 = 3桁(千の位への繰り上がりなし)
  loop { a = rand(100..999); b = rand(100..999); break [a, b] if a + b <= 999 }
end
def_pattern('P2-1-9', :add) do   # 3桁 + 3桁 = 4桁(千の位への繰り上がりあり)
  loop { a = rand(100..999); b = rand(100..999); break [a, b] if a + b >= 1000 }
end

# ---- 制約(コスト関数)---------------------------------------------------
# 1 回内で「総コストを上限以下に保つ」ための各問コスト関数。
# adjust! がコストの正の問題を差し替えて総コストを調整する(下記参照)。
COST_ONES     = ->(p) { ones_in(p) }              # 被演算数(a,b)に現れる '1' の個数
COST_B_ONES   = ->(p) { p[:b].to_s.count('1') }   # 減数(b)に現れる '1' の個数
COST_ZERO_ANS = ->(p) { p[:ans].zero? ? 1 : 0 }   # 答えが 0 なら 1
COST_ZERO_TEN_ANS = ->(p) { [0, 10].include?(p[:ans]) ? 1 : 0 } # 答えが 0 または 10 なら 1
COST_A_TEN    = ->(p) { p[:a] == 10 ? 1 : 0 }     # 被減数(a)が 10 なら 1
# 被加数・加数の一の位に現れる '0' と '1' の個数(0〜2)
COST_UNITS_ZERO_ONE = ->(p) { [p[:a] % 10, p[:b] % 10].count { |d| [0, 1].include?(d) } }
# 被加数(a)の十の位が '1' なら 1
COST_A_TENS_ONE = ->(p) { p[:a] / 10 % 10 == 1 ? 1 : 0 }
# 被加数(a)の十の位が '0' または '1' なら 1
COST_A_TENS_ZERO_ONE = ->(p) { [0, 1].include?(p[:a] / 10 % 10) ? 1 : 0 }
# 被加数・加数の十の位に現れる '0' と '1' の個数(0〜2)
COST_TENS_ZERO_ONE = ->(p) { [p[:a] / 10 % 10, p[:b] / 10 % 10].count { |d| [0, 1].include?(d) } }
# 1 問の中で被演算数どうしが似すぎなら 1。同じ桁数で相違する桁が 1 つ以下
# (649 + 639 や 136 + 136 など)を「似すぎ」とする。桁数が違えば似ていない。
# 1 桁どうしは必ず相違 1 桁以下になるため、2 桁以上のみを対象とする。
COST_SIMILAR_AB = lambda do |p|
  sa = p[:a].to_s
  sb = p[:b].to_s
  next 0 unless sa.size == sb.size && sa.size >= 2

  sa.chars.zip(sb.chars).count { |x, y| x != y } <= 1 ? 1 : 0
end

# 筆算-加算ステージの制約セット。1 問内で被加数と加数が似すぎるのを禁止(上限 0)
# するのと、一の位の '0'/'1' は 1 回までが共通。十の位の条件だけがステージの
# 進行につれて広がる。
CONSTR_SIMILAR         = [[COST_SIMILAR_AB, 0]].freeze
CONSTR_A_TENS_ONE      = (CONSTR_SIMILAR + [[COST_UNITS_ZERO_ONE, 1], [COST_A_TENS_ONE, 2]]).freeze
CONSTR_A_TENS_ZERO_ONE = (CONSTR_SIMILAR + [[COST_UNITS_ZERO_ONE, 1], [COST_A_TENS_ZERO_ONE, 2]]).freeze
CONSTR_TENS_ZERO_ONE   = (CONSTR_SIMILAR + [[COST_UNITS_ZERO_ONE, 1], [COST_TENS_ZERO_ONE, 2]]).freeze

# ---- ステージ定義 ------------------------------------------------------
# entries: [[パターン候補配列, 問題数], ...]。候補が複数なら等確率で 1 つ選ぶ。
# constraints: [[コスト関数, 上限], ...]。1 回内で総コストを上限以下に調整する。
# special: :kuku のステージは問題数・並び順・回数が固定(CLI 指定を無視)。
STAGES = {
  'S1-1-1' => { subtitle: 'たしざん暗算1', scale: :large, constraints: [[COST_ONES, 2]],
                entries: [[%w[P1-1-1], 10]] },
  'S1-1-2' => { subtitle: 'たしざん暗算2', scale: :large, constraints: [[COST_ONES, 1]],
                entries: [[%w[P1-1-1], 2], [%w[P1-1-2], 2], [%w[P1-1-3], 6]] },
  'S1-1-3' => { subtitle: 'たしざん暗算3', scale: :large, constraints: [[COST_ONES, 1]],
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 8]] },
  'S1-1-4' => { subtitle: 'たしざん暗算4', scale: :large,
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 3], [%w[P1-1-5], 5]] },
  'S1-1-5' => { subtitle: 'たしざん暗算5', scale: :large,
                entries: [[%w[P1-1-3], 2], [%w[P1-1-6], 8]] },
  'S1-2-1' => { subtitle: 'ひきざん暗算1', scale: :large,
                constraints: [[COST_B_ONES, 1], [COST_A_TEN, 2], [COST_ZERO_ANS, 1]],
                entries: [[%w[P1-2-1], 10]] },
  'S1-2-2' => { subtitle: 'ひきざん暗算2', scale: :large,
                constraints: [[COST_B_ONES, 1], [COST_ZERO_TEN_ANS, 1]],
                entries: [[%w[P1-2-1], 2], [%w[P1-2-2], 8]] },
  'S1-3-1' => { subtitle: 'かけざん暗算1', scale: :medium, special: :kuku },
  'S1-3-2' => { subtitle: 'かけざん暗算2', scale: :medium, entries: [[%w[P1-3-1], 20]] },
  'S1-3-3' => { subtitle: 'かけざん暗算3', scale: :medium, entries: [[%w[P1-3-2], 20]] },
  'S1-3-4' => { subtitle: 'かけざん暗算4', scale: :small, entries: [[%w[P1-3-3], 20]] },
  'S1-3-5' => { subtitle: 'かけざん暗算5', scale: :small, entries: [[%w[P1-3-4], 20]] },
  'S1-3-6' => { subtitle: 'かけざん暗算6', scale: :small, entries: [[%w[P1-3-5], 10], [%w[P1-3-6], 10]] },
  'S2-1-1' => { subtitle: 'たしざん筆算1', scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-1], 12]] },
  'S2-1-2' => { subtitle: 'たしざん筆算2', scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-1], 4], [%w[P2-1-2], 8]] },
  'S2-1-3' => { subtitle: 'たしざん筆算3', scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-3], 4], [%w[P2-1-4], 8]] },
  'S2-1-4' => { subtitle: 'たしざん筆算4', scale: :large, constraints: CONSTR_A_TENS_ZERO_ONE,
                entries: [[%w[P2-1-4], 1], [%w[P2-1-5], 3], [%w[P2-1-6], 8]] },
  'S2-1-5' => { subtitle: 'たしざん筆算5', scale: :large, constraints: CONSTR_TENS_ZERO_ONE,
                entries: [[%w[P2-1-7], 1], [%w[P2-1-8], 5], [%w[P2-1-9], 6]] }
}.freeze

def stage_num(stage)
  stage[:entries].sum { |_pats, count| count }
end

# ステージの出題形式(:mental / :column)。九九(entries 無し)は暗算。
def stage_form(stage)
  return :mental unless stage[:entries]

  pattern_form(stage[:entries].first[0].first)
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
  ans = case op
        when :add then a + b
        when :sub then a - b
        when :mul then a * b
        end
  { a: a, b: b, op: op, ans: ans, pid: pat[:id] }
end

# 被演算数(a, b)に含まれる数字 '1' の個数。
def ones_in(prob)
  prob[:a].to_s.count('1') + prob[:b].to_s.count('1')
end

# ---- 出題履歴(重複回避)------------------------------------------------
# 「回をまたいだ再出現」を避ける対象とする直近の回数。
RECENT_SETS = 3

# 重複回避の厳しさ。上の段から順に試し、UNIQUE_ATTEMPTS 回で見つからなければ
# 1 段緩める。候補が少ないパターンでも必ず 1 問返せるようにするための仕組み。
#   :strict      直近の回に出た問題・数値も避ける(回内の重複回避も含む)
#   :recent_key  直近の回に出た問題のみ避ける(数値の再出現は許す)
#   :in_set_near 回内で同じ問題・同じ数値・1 桁違いの数値を使わない
#   :in_set      回内で同じ問題・同じ数値を使わない(1 桁違いは許す)
#   :key         回内で同じ問題を使わない
#   :any         重複を許容する(最終手段)
VARIETY_LEVELS = %i[strict recent_key in_set_near in_set key any].freeze
PLAIN_LEVELS   = %i[key any].freeze

# 出題履歴を作る。
#   keys   : 回内で既出の問題キー([a, b, op])→ 出現数
#   values : 回内で既出の被演算数の値 → 出現数
#   recent : 直近 RECENT_SETS 回分の [問題キー配列, 数値配列](古い順)
#   variety: 真なら数値の使い回しと直近の回との重複も避ける。候補が数十通り
#            しかない暗算(1 桁)では成立しないため、筆算のみで真にする。
def new_history(variety: false)
  { keys: Hash.new(0), values: Hash.new(0), recent: [], variety: variety }
end

def prob_key(prob)
  [prob[:a], prob[:b], prob[:op]]
end

# 数値の使い回しを見る対象。1 桁の数は候補が 9 通りしかなく、繰り返しても
# 「似た問題」には見えないため対象外とする。1 問内の a == b も 1 個と数える。
def prob_values(prob)
  [prob[:a], prob[:b]].uniq.select { |v| v >= 10 }
end

# 問題を履歴に記録する(記録した問題をそのまま返す)。
def record(hist, prob)
  hist[:keys][prob_key(prob)] += 1
  prob_values(prob).each { |v| hist[:values][v] += 1 }
  prob
end

# 差し替えで取り除く問題の記録を取り消す。
def unrecord(hist, prob)
  hist[:keys][prob_key(prob)] -= 1
  prob_values(prob).each { |v| hist[:values][v] -= 1 }
end

# 回内の既出の数値に「同じ桁数で相違 1 桁」のものがあるか(例: 175 と 174、
# 987 と 957)。3 桁以上のみを対象とする。2 桁では相違 1 桁を避けきれない
# (相互に 2 桁以上異なる 2 桁の数は最大 10 個しかなく、1 回 24 個は不可能)。
def near_dup?(hist, prob)
  prob_values(prob).select { |v| v >= 100 }.any? do |v|
    sv = v.to_s
    hist[:values].any? do |w, count|
      next false unless count.positive?

      sw = w.to_s
      sw.size == sv.size && sw.chars.zip(sv.chars).count { |x, y| x != y } == 1
    end
  end
end

# level の基準で prob が「重複」に当たるか。
def dup?(hist, prob, level)
  return false if level == :any
  return true if hist[:keys][prob_key(prob)].positive?
  # 1 問内の被演算数どうしの類似(649 + 639 など)。ステージ制約と同じ判定を
  # 使う。1 問だけで判定できる条件で必ず満たせるため、緩和の対象にしない。
  return true if hist[:variety] && COST_SIMILAR_AB.call(prob).positive?
  return false if level == :key
  return true if prob_values(prob).any? { |v| hist[:values][v].positive? }
  return false if level == :in_set
  return true if near_dup?(hist, prob)
  return false if level == :in_set_near
  return true if hist[:recent].any? { |keys, _vals| keys.include?(prob_key(prob)) }
  return false if level == :recent_key

  vals = prob_values(prob)
  hist[:recent].any? { |_keys, prev| vals.any? { |v| prev.include?(v) } }
end

# 1 回分が確定したら呼ぶ。回内の記録を「直近の回」へ移して次の回に備える。
def close_set!(hist)
  positive = ->(h) { h.select { |_k, c| c.positive? }.keys }
  hist[:recent] << [positive.call(hist[:keys]), positive.call(hist[:values])]
  hist[:recent].shift while hist[:recent].size > RECENT_SETS
  hist[:keys] = Hash.new(0)
  hist[:values] = Hash.new(0)
  hist
end

def dup_levels(hist)
  hist[:variety] ? VARIETY_LEVELS : PLAIN_LEVELS
end

# 履歴と重複しない問題を生成して返す。pats が複数なら毎回等確率で選び直す。
# 厳しい基準から順に試し、見つからなければ 1 段緩める。
def gen_unique(pats, hist)
  dup_levels(hist).each do |level|
    UNIQUE_ATTEMPTS.times do
      prob = gen_problem(pats.sample)
      return record(hist, prob) unless dup?(hist, prob, level)
    end
  end
  # 最後の段は :any(無条件で採用)なので、通常ここへは到達しない。
  record(hist, gen_problem(pats.sample))
end

# 問題配列に通し番号を付与する。
def numbered(probs)
  probs.each_with_index.map { |p, i| p.merge(n: i + 1) }
end

# 同じ数値が隣り合いにくいよう貪欲に並べ替える(分布は変えず順序のみ調整)。
# ランダムに崩した並びを起点に、直前の問題と数値(a, b)を共有しない候補を優先して
# 前から詰める。共有しない候補が無ければ先頭の残りを置く(範囲が狭いと発生しうる)。
def spread_order(probs)
  rest = probs.shuffle
  ordered = [rest.shift]
  until rest.empty?
    prev = [ordered.last[:a], ordered.last[:b]]
    i = rest.index { |p| ([p[:a], p[:b]] & prev).empty? } || 0
    ordered << rest.delete_at(i)
  end
  ordered
end

# 同一パターン(pid)で全コスト関数が 0 になる問題を、可能な限り重複せず生成する。
# 重複回避は gen_unique と同じ段階で緩める(コスト 0 の条件は最後まで維持)。
def gen_zero_cost(pid, hist, costs)
  zero = ->(prob) { costs.all? { |c| c.call(prob).zero? } }
  dup_levels(hist).each do |level|
    UNIQUE_ATTEMPTS.times do
      prob = gen_problem(pid)
      next unless zero.call(prob)

      return record(hist, prob) unless dup?(hist, prob, level)
    end
  end
  record(hist, gen_problem(pid)) # 最終手段: コスト 0 も諦める
end

# 1 回内で cost の総和を max 以下に調整する。cost が正の問題を問題番号(n)の
# 大きい順に、全コスト関数が 0 となる同一パターン問題へ差し替える。差し替え後の
# 問題は全コストが 0 なので、繰り返すと総和は必ず減り、既に満たした制約も壊さない。
#   all_costs : ステージの全コスト関数(差し替え先が全制約を満たすようにする)
def adjust!(set, hist, cost, max, all_costs)
  loop do
    break if set.sum { |p| cost.call(p) } <= max

    target = set.select { |p| cost.call(p).positive? }.max_by { |p| p[:n] }
    break unless target

    unrecord(hist, target)
    repl = gen_zero_cost(target[:pid], hist, all_costs).merge(n: target[:n])
    set[set.index { |p| p[:n] == target[:n] }] = repl
  end
  set
end

# 前半(左側)に並べる問題数。半分(奇数なら切り上げ)。
def left_count(num)
  (num + 1) / 2
end

# ステージ 1 回分を生成。重複回避の範囲は hist(出題履歴)が決める。
def make_stage_set(stage, hist)
  probs = []
  stage[:entries].each do |pats, count|
    count.times { probs << gen_unique(pats, hist) }
  end
  set = numbered(probs.shuffle)
  if stage[:constraints]
    all_costs = stage[:constraints].map { |cost, _max| cost }
    stage[:constraints].each { |cost, max| adjust!(set, hist, cost, max, all_costs) }
  end
  close_set!(hist)
  # 制約調整(差し替え)後に、隣接での数値重複が減るよう最終的な並びを整える。
  numbered(spread_order(set))
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

# --pattern/--ratio 指定の 1 回分を生成。重複回避の範囲は hist が決める。
def make_pattern_set(patterns, ratios, num, hist)
  counts = allocate_counts(ratios, num)
  probs = []
  patterns.each_with_index { |pid, i| counts[i].times { probs << gen_unique([pid], hist) } }
  close_set!(hist)
  numbered(spread_order(probs))
end

# 丸数字(①..⑳ / ㉑..㉟)を返す。
def circled(n)
  cp = n <= 20 ? 0x2460 + (n - 1) : 0x3251 + (n - 21)
  [cp].pack('U')
end

# ---- Typst 生成 --------------------------------------------------------

# 問題テーブルのセル配列(Typst の array of dict リテラル)。
# 筆算(:column)は数字・演算子とも全角で渡す。暗算(:mental)は半角のまま
# (1 つのテキストランで組むため、全角にすると字送りが valw を超える)。
def typ_problems(items, form = :mental)
  '(' + items.map { |p|
    if form == :column
      %{(n: "#{circled(p[:n])}", a: "#{zen_digits(p[:a])}", b: "#{zen_digits(p[:b])}", op: "#{OP_SYM_ZEN[p[:op]]}")}
    else
      %{(n: "#{circled(p[:n])}", a: #{p[:a]}, b: #{p[:b]}, op: "#{OP_SYM[p[:op]]}")}
    end
  }.join(', ') + ',)'
end

# 解答テーブルのセル配列
def typ_answers(items)
  '(' + items.map { |p| %{(n: "#{circled(p[:n])}", p: #{p[:ans]})} }.join(', ') + ',)'
end

# 暗算・筆算で共通の前文(フォント・見出し・切り取り線・A4 横 1 ページの組み方)。
def typ_preamble(title_text, stage_name, form, tag)
  <<~TYP
    // 自動生成ファイル (arithprac.rb) — 直接編集しないでください。
    #set text(font: "#{JP_FONT}", size: 12pt, lang: "ja")

    // ステージ名(ステージ指定時のみ。空文字なら非表示)。「第N回」の左に置く。
    #let stagename = "#{stage_name}"

    #let ansfs = 10pt  // 解答の文字サイズ(人間が読みやすい固定サイズ)

    // --- ページ下端のタグ(印刷後に問題と解答を対応づけるための識別子) ---
    // 用紙の左下から #{TAG_MARGIN}mm / #{TAG_MARGIN}mm。本文マージンの外側に置く。
    #let tag = "#{tag}"
    #let tagmark(dx) = place(bottom + left, dx: dx, dy: -#{TAG_MARGIN}mm)[
      #text(size: #{TAG_FS}pt, fill: luma(#{TAG_LUMA}))[#tag]]
    // 問題(A4 横)は A5×2 に切るため、左右それぞれの左下に入れる。
    #let tagprob = { tagmark(#{TAG_MARGIN}mm); tagmark(#{A5_WIDTH + TAG_MARGIN}mm) }
    // 解答(A4 縦)は左下 1 箇所。
    #let tagans = tagmark(#{TAG_MARGIN}mm)

    // A5 1 枚(1 回分)の見出し。大見出し・回・名前・得点、最後に問題本体との空き。
    #let probhead(title) = [
      #align(center)[#text(size: 18pt, weight: "bold")[#{title_text}]]
      #v(3pt)
      #align(center)[#text(size: 10pt)[
        #if stagename != "" [#stagename #h(6mm)]#title #h(8mm) 名前 #box(width: 28mm, stroke: (bottom: 0.5pt))[] #h(4mm) 得点 #box(width: 14mm, stroke: (bottom: 0.5pt))[]
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

# 問題(暗算)の定義。1 問 = 6 セルの行、A5 1 枚は前半/後半の 2 列。
def typ_mental_defs(scale)
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
      #probhead(title)
      // 左(前半)と右(後半)を区切る点線。線をやや左に寄せ、右列の番号との隙間を広めに。
      #grid(columns: (1fr, 1.5mm, 6mm, 1fr), align: top,
        grid.vline(x: 2, stroke: (paint: luma(140), thickness: 0.6pt, dash: "dotted")),
        probtable(left), [], [], probtable(right))
    ])
  TYP
end

# 問題(筆算)の定義。見出し以降の残り領域を num 個のリージョンに等分し、
# 1 リージョンに 1 問(右上寄せ)を配置する。番号はリージョンの左上に置く。
def typ_column_defs(scale, num)
  s = COLUMN_SCALES[scale]
  rows, cols = REGION_SHAPES[num]
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

    // リージョンの区切り点線(外周には引かない)
    #let regionline = (paint: luma(140), thickness: 0.4pt, dash: "dotted")

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

# 解答(A4 縦)。暗算・筆算で共通。
def typ_answer_defs
  <<~TYP

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
  TYP
end

# 問題ページ(A4 横。2 回分ずつ)。
#   暗算: 前半 ln 問を左、残りを右に並べる。 筆算: 1 回分をそのまま渡す。
def typ_problem_pages(sets, num, form)
  ln = left_count(num)
  out = +''
  (0...sets.size).step(2) do |i|
    a = sets[i]
    b = sets[i + 1]
    args = if form == :column
             ["\"第#{i + 1}回\", #{typ_problems(a, form)}", "\"第#{i + 2}回\", #{typ_problems(b, form)}"]
           else
             ["\"第#{i + 1}回\", #{typ_problems(a[0...ln])}, #{typ_problems(a[ln...num])}",
              "\"第#{i + 2}回\", #{typ_problems(b[0...ln])}, #{typ_problems(b[ln...num])}"]
           end
    out << %{\n#sheetpair(\n  probset(#{args[0]}),\n  probset(#{args[1]}),\n)\n}
    out << "#pagebreak()\n" if i + 2 < sets.size
  end
  out
end

def build_typst(sets, num, title_text, stage_name, scale, form, tag)
  out = +''
  out << typ_preamble(title_text, stage_name, form, tag)
  out << (form == :column ? typ_column_defs(scale, num) : typ_mental_defs(scale))
  out << typ_answer_defs
  out << <<~TYP

    // ================= 問題(A4 横) =================
    #set page(paper: "a4", flipped: true, margin: (x: 6mm, y: 8mm), background: tagprob)
  TYP
  out << typ_problem_pages(sets, num, form)

  # ================= 解答(A4 縦) =================
  out << <<~TYP

    #set page(flipped: false, margin: (x: 10mm, y: 10mm), background: tagans)
    #align(center)[#text(size: 16pt, weight: "bold")[#{title_text}#if stagename != "" [ #stagename] 解答]]
    #v(6pt)
    #grid(columns: (1fr, 1fr, 1fr, 1fr), column-gutter: 3mm, row-gutter: 6pt,
  TYP

  ln = left_count(num)
  sets.each_with_index do |s, i|
    out << %{  ansblock("第#{i + 1}回", #{typ_answers(s)}, #{ln}),\n}
  end
  out << ")\n"

  out
end

# ---- メイン ------------------------------------------------------------

main = lambda do
options = { pages: nil, num: nil, seed: nil,
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
  o.on('-n N', '--num N', Integer,
       "1 回あたりの問題数(暗算: #{MIN_PROBLEMS}〜#{MAX_PROBLEMS}, 既定 #{DEFAULT_PROBLEMS} / " \
       "筆算: #{REGION_SHAPES.keys.join('・')} のいずれか, 既定 #{DEFAULT_REGIONS})") { |v| options[:num] = v }
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

# seed は未指定でも必ず確定させる(印刷後の対応づけと再現のため)。
# 完全な seed はログにのみ出力し、紙面には下位 16bit を 16 進 4 文字で入れる。
seed = options[:seed] || Random.new_seed
srand(seed)
tag = format('%04X', seed & 0xFFFF)
puts "seed = #{seed}#{options[:seed] ? '' : '(自動生成)'} で生成します。ページタグ: #{tag}"

pages = options[:pages] || DEFAULT_PAGES
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
stage_name = nil  # ステージ指定時のみサブタイトルを「第N回」の左に表示する
scale = DEFAULT_SCALE
form = :mental    # 出題形式(:mental=暗算 / :column=筆算)

if options[:stage]
  key = options[:stage].upcase
  stage = STAGES[key]
  abort "エラー: ステージ '#{options[:stage]}' は存在しません(一覧は --stage-list)。" unless stage
  warn '警告: --stage 指定時は --pattern/--ratio/--num は無視されます。' if !options[:patterns].empty? || !options[:ratios].empty? || options[:num]
  warn '警告: --stage 指定時は --scale は無視されます(ステージ固有のスケールを使用)。' if scale_opt
  stage_name = stage[:subtitle]
  scale = stage[:scale] # ステージ指定時は --scale を無視しステージ固有スケールを使う
  form = stage_form(stage)

  if stage[:special] == :kuku
    # 九九: 問題数・並び順・回数(4)が固定。--pages も無視。
    sets = make_kuku_sets
    num = 16
    puts "ステージ #{key}(#{stage[:subtitle]}): 九九固定 4 回・1 回 16 問(scale=#{scale}, CLI 指定は無視)。"
  else
    num = stage_num(stage)
    # 筆算は問題数 = リージョン数。分割できない問題数のステージは定義ミス。
    if form == :column && !REGION_SHAPES.key?(num)
      abort "内部エラー: ステージ #{key} の問題数(#{num})はリージョンに分割できません" \
            "(#{REGION_SHAPES.keys.join(' / ')})。"
    end
    # 履歴は全回で共有する(回をまたいだ重複回避のため)。
hist = new_history(variety: form == :column)
sets = Array.new(sets_count) { make_stage_set(stage, hist) }
    puts "ステージ #{key}(#{stage[:subtitle]}): #{pages} ページ・#{sets_count} 回・1 回 #{num} 問" \
         "(form=#{form}, scale=#{scale})。"
  end

elsif !options[:patterns].empty?
  patterns = options[:patterns]
  unknown = patterns.reject { |p| PATTERNS.key?(p.upcase) }
  abort "エラー: パターンが存在しません: #{unknown.join(', ')}" unless unknown.empty?

  forms = patterns.map { |p| pattern_form(p) }.uniq
  abort 'エラー: 暗算(P1-x-x)と筆算(P2-x-x)のパターンは同時に指定できません。' if forms.size > 1
  form = forms.first

  if form == :column
    # 筆算: 問題数がリージョン分割形を決めるため、分割できる値のみ受け付ける。
    num = options[:num] || DEFAULT_REGIONS
    unless REGION_SHAPES.key?(num)
      abort "エラー: 筆算の問題数は #{REGION_SHAPES.keys.join(' / ')} のいずれかを指定してください(指定: #{num})。"
    end
  else
    num = options[:num] || DEFAULT_PROBLEMS
    unless (MIN_PROBLEMS..MAX_PROBLEMS).include?(num)
      abort "エラー: 問題数は #{MIN_PROBLEMS}〜#{MAX_PROBLEMS} の範囲で指定してください(指定: #{num})。"
    end
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
  hist = new_history(variety: form == :column)
sets = Array.new(sets_count) { make_pattern_set(patterns, ratios, num, hist) }
  puts "パターン #{patterns.join(', ')}: #{sets_count} 回・1 回 #{num} 問(form=#{form}, scale=#{scale})。"

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

# 大見出しは出題形式で決まる。
title_text = form == :column ? '筆算マスター' : '暗算マスター'

File.write(typ_path, build_typst(sets, num, title_text, stage_name, scale, form, tag))
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
