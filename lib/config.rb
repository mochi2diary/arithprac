# frozen_string_literal: true

# 設定(定数・スケール・小ヘルパ)。arithprac.rb から最初に読み込まれる。

# ---- 設定 --------------------------------------------------------------
SETS             = 10  # 回数(A5 の枚数)の既定値。実際は 2 * pages。
DEFAULT_PAGES    = 10  # 問題ページ数の既定値(1 ページ = 2 回分 → 既定 20 回分)
DEFAULT_PROBLEMS = 20  # 1 回あたりの問題数の既定値(--pattern 使用時)
MIN_PROBLEMS     = 2   # 1 回あたりの問題数の下限
MAX_PROBLEMS     = 26  # 1 回あたりの問題数の上限
DEFAULT_REGIONS  = 6   # 筆算の 1 回あたりの問題数(= リージョン数)の既定値
DEFAULT_CLOCK_REGIONS = 4 # 時計(よみ)の 1 回あたりの問題数(= リージョン数)の既定値
JP_FONT          = 'BIZ UDGothic'
# 筆算の数字・演算子だけに使うフォント(本文の JP_FONT とは独立に選ぶ)。
COLUMN_DIGIT_FONT = 'BIZ UDGothic'
BASENAME         = 'arithprac'

# 筆算・時計のリージョン分割形 { 問題数(= リージョン数) => [縦の個数(行), 横の個数(列)] }
REGION_SHAPES = { 12 => [4, 3], 8 => [4, 2], 6 => [3, 2], 4 => [2, 2], 1 => [1, 1] }.freeze

# ページ下端のタグ(シード下位 16bit の 16 進 4 文字)。印刷後に問題と解答を対応づける。
# 問題(A4 横)は切り離した A5 の左下それぞれに、解答(A4 縦)は左下 1 箇所に入れる。
TAG_MARGIN_X = 5    # 用紙の左端からの距離(mm)。本文マージン(6mm)のすぐ外側。
TAG_MARGIN_Y = 8    # 用紙の下端からの距離(mm)。下端は不可印字領域が広い機種があるため広めにとる。
TAG_FS     = 6      # タグの文字サイズ(pt)
TAG_LUMA   = 80     # タグの文字色(luma。小さいほど濃い)
A5_WIDTH   = 148.5  # A4 横を 2 分割した A5 1 枚の幅(mm)

# 見出し(回・名前・得点)と問題本体の間の空き(pt)。出題形式ごとに異なる。
HEAD_GAP = { mental: 8, column: 12, clock: 12 }.freeze

# 演算子記号(表示用)。筆算は全角を使う(半角より字形が広く、字間が行間と釣り合う)。
OP_SYM     = { add: '+', sub: '−', mul: '×' }.freeze
OP_SYM_ZEN = { add: '＋', sub: '－', mul: '×' }.freeze

# スケール(文字・解答欄サイズ)。値は pt / mm(単位はテンプレート側で付与)。
#   inset_y : 問題行の行間(y)         valfs : 数値・等号のフォント
#   opfs    : 演算子(+/×)のフォント   boxw/boxh : 解答欄の幅・高さ
#   answ    : 解答ページの答えの欄幅(既定 ANSW_DEFAULT)
#   anscols : 解答ページに横に並べる回数(既定 ANSCOLS_DEFAULT)
#   ansrowgap : 解答ブロックの行間(pt。既定 ANSROWGAP_DEFAULT)
# oneline: true のスケールは 1 列レイアウト(式を 1 セルに収める)。式のフォントは
# valfs/opfs ではなく exprfs で指定する。小数のように桁数が伸びる問題に使う。
SCALES = {
  small:    { inset_y: 10, valfs: 13, opfs: 12, boxw: 26, boxh: 9 },
  medium:   { inset_y: 11, valfs: 14, opfs: 13, boxw: 26, boxh: 12 },
  large:    { inset_y: 20, valfs: 16, opfs: 15, boxw: 26, boxh: 18 },
  # inset_y は A5 に 15 問を収めるため 3pt(CLAUDE.md の 10pt では 1 問 16mm となり
  # 使える高さ約 170mm に 11 問しか入らない)。
  # answ は小数の答えの分(最長 9 文字 = 15.9mm)。解答を横 6 回分並べるため 18mm。
  # ansrowgap 3pt は解答ブロック 4 行(= 24 回分)を A4 縦 1 ページに収めるため
  # (既定の 6pt では 4 行で 266mm となり、使える高さ約 265mm に収まらない)。
  onesmall: { inset_y: 3, exprfs: 12, boxw: 70, boxh: 9, oneline: true,
              answ: 18, anscols: 6, ansrowgap: 3 }
}.freeze
DEFAULT_SCALE = :small
ANSW_DEFAULT      = 12  # 解答の欄幅(mm)。整数の答えは最大 4 桁(9801)で収まる。
ANSNUMW_DEFAULT   = 6   # 解答の番号(丸数字)の欄幅(mm)
ANSCOLS_DEFAULT   = 4   # 解答ページに横に並べる回数
ANSROWGAP_DEFAULT = 6   # 解答ブロックの行間(pt)

# 1 列レイアウト(前半/後半に分けず、全問を上から下へ 1 列に並べる)か。
def oneline?(scale)
  SCALES[scale][:oneline] ? true : false
end

# 解答ページに横に並べる回数。1 列レイアウトは解答ブロックが細いため多く並べられる。
# 時計は答えが長く(例: 0 じ(12 じ) 55 ふん)ブロックが広いため少なくする。
def ans_cols(scale, form = :mental)
  return CLOCK_ANSCOLS if form == :clock

  SCALES[scale][:anscols] || ANSCOLS_DEFAULT
end

# 解答ページの答えの欄幅(mm)。
def ans_width(scale, form = :mental)
  return CLOCK_ANSW if form == :clock

  SCALES[scale][:answ] || ANSW_DEFAULT
end

# 解答ページの番号(丸数字)の欄幅(mm)。時計は答えが長いぶんここを詰める。
def ans_num_width(form)
  form == :clock ? CLOCK_ANSNUMW : ANSNUMW_DEFAULT
end

# 解答ブロックの前半(左列)に置く問題数。時計は答えが長いため 1 列に並べる。
def ans_left_count(num, scale, form)
  form == :clock ? num : left_count(num, scale)
end

# 解答ブロックの行間(pt)。1 列レイアウトはブロックが縦に長いため詰める。
def ans_row_gap(scale)
  SCALES[scale][:ansrowgap] || ANSROWGAP_DEFAULT
end

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

# 時計(よみ)のレイアウト。文字・盤面の大きさはリージョンに合わせて決まるため
# --scale の影響を受けない(時計盤はリージョンに収まる範囲で diam まで大きくする)。
# 値は mm / pt。
CLOCK_LAYOUT = {
  diam: 60,      # 時計盤の直径(リージョンに入らなければ縮める)
  boxh: 18,      # 解答欄の高さ
  boxover: 5,    # 解答欄が時計盤からはみ出す幅(左右それぞれ)
  boxr: 5,       # 解答欄の角丸の半径
  boxthk: 0.7,   # 解答欄の線の太さ(pt)
  gap: 3,        # 時計盤と解答欄のあいだの空き
  unitfs: 10,    # 「じ」「ふん」の文字サイズ(pt)
  unitgap: 3,    # 解答欄の下端から「じ」「ふん」の下端までの距離
  fun_dx: 3,     # 「ふん」の右端を角丸の始まりから右へずらす量
  ji_dx: 2,      # 「ふん」があるとき「じ」の右端を解答欄の中央から左へずらす量
  itis_dx: 3,    # (英語)「It is」の左端を角丸の終わりから左へずらす量
  period_dx: 3,  # (英語)「．」の右端を角丸の始まりから右へずらす量
  period_fs: 12, # (英語)「．」の文字サイズ(pt)。「It is」は unitfs を使う。
  line_gap: 2,   # (英語)下線の両端と「It is」「．」のあいだの空き
  en_lift: 5,    # (英語)「It is」・下線・「．」の全体を上へずらす量
  rpad_x: 3,     # リージョン内の左右の余白
  rpad_y: 3      # 同・上下の余白
}.freeze
# 解答ページの寸法。答えが「0 じ(12 じ) 55 ふん」のように長い(10pt で 33.6mm)ため
# 欄幅を広くとり、そのぶん番号欄を詰めて他の形式と同じ横 4 回分に収める。
# ブロック幅 = anspad 2mm × 2 + 番号欄 + 答えの欄幅 = 45mm。
# 45mm × 4 + 隙間 3mm × 3 = 189mm で、A4 縦の使える幅(190mm)に収まる。
CLOCK_ANSW    = 36  # 答えの欄幅(mm)
CLOCK_ANSNUMW = 5   # 番号(丸数字)の欄幅(mm)。丸数字 3.5mm + セル内側 2pt × 2。
CLOCK_ANSCOLS = 4   # 解答ページに横に並べる回数

