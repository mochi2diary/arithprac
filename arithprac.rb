# frozen_string_literal: true

# arithprac — 算数の計算問題・解答ジェネレータ
#
# 動作要件: Ruby 4.0 以降（標準ライブラリのみ）
# 出力     : Typst ファイル(.typ)を生成し、typst でコンパイルして PDF を得る
#
# 出題形式:
#   - 暗算(P1-x-x): 式を 1 行に並べ、右端の□に答えを書かせる。
#   - 筆算(P2-x-x): 1 回分の領域をリージョンに等分割し、1 問ずつ筆算の形で置く。
#   - 時計(P4-x-x): 同じくリージョンに等分割し、1 問ずつ時計盤と解答欄を置く。
#
# 生成物:
#   - 問題 : A4 横(landscape)を中央で 2 分割して A5×2。1 枚(A5)に 1 回分。
#            1 ページ = 2 回分。--pages で回数を制御(回数 = 2 * pages)。
#            中央に切り取り線を入れる。
#            暗算は左に前半・右に後半を並べる(奇数個なら左が 1 つ多い)。
#            筆算・時計は 1 回分を --num 個のリージョンに分けて行優先に並べる。
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

# ---- 多言語対応 --------------------------------------------------------
# 言語依存の文字列(画面と紙面に出るもの)は、すべてこの節の TEXTS に集める。
# コード中の他の場所には日本語・英語を直接書かない。
# ソースおよび生成される .typ 内のコメントは、利用者向けの出力ではないため
# 言語によらず日本語のままとする。
LANGS        = %i[ja en].freeze
DEFAULT_LANG = :ja
EN_FONT      = JP_FONT  # 英語のフォント(現時点では日本語と同じものを使う)
FONTS        = { ja: JP_FONT, en: EN_FONT }.freeze

# 実行時に選ばれている言語。--lang で書き換える(既定は DEFAULT_LANG)。
CURRENT_LANG = { lang: DEFAULT_LANG }

# 英語の数詞(0〜59)。時計(よみ)の解答を数字ではなく英単語で書くために使う。
EN_ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen
             fourteen fifteen sixteen seventeen eighteen nineteen].freeze
EN_TENS = %w[twenty thirty forty fifty].freeze
EN_NUMBERS = (0..59).map do |n|
  next EN_ONES[n] if n < 20

  tens = EN_TENS[n / 10 - 2]
  (n % 10).zero? ? tens : "#{tens}-#{EN_ONES[n % 10]}"
end.freeze

def lang = CURRENT_LANG[:lang]

def lang!(sym)
  CURRENT_LANG[:lang] = sym
end

# 本文・時計盤の数字に使うフォント。
def body_font = FONTS[lang]

# 言語依存の文字列を取り出す。%{...} を含むものは名前付き引数で埋める。
def t(key, **args)
  s = TEXTS.fetch(lang).fetch(key)
  args.empty? ? s : format(s, **args)
end

# 時計(よみ)の解答に出す数字。英語は数字ではなく英単語で書く(:numbers が有れば使う)。
def clock_num(n)
  words = TEXTS.fetch(lang)[:numbers]
  words ? words[n] : n.to_s
end

# 同じく「ふん」の数。1 桁のふんは英語では "oh" を付けて読む(例: three oh five)。
def clock_min_num(m)
  fmt = TEXTS.fetch(lang)[:clock_min_oh]
  s = clock_num(m)
  fmt && m < 10 ? format(fmt, m: s) : s
end

# ステージのサブタイトル(--stage-list の一覧と紙面の見出しに使う)。
def stage_subtitle(id)
  TEXTS.fetch(lang)[:subtitles][id.upcase]
end

TEXTS = {
  ja: {
    # --- 紙面(PDF)---
    title_mental: '暗算マスター',
    title_column: '筆算マスター',
    title_clock:  '時計マスター',
    name:         '名前',
    score:        '得点',
    answers:      '解答',
    ans_head_sep: ' ',   # 解答ページの見出しで大見出し・ステージ名・「解答」を区切る字
    set_no:       '第%{n}回',
    # 時計(よみ)の解答欄に出す字と、解答の文字列。
    # 「0 じ」は「12 じ」とも読めるため併記する。
    clock_hour_unit: 'じ',
    clock_min_unit:  'ふん',
    clock_h0:        '0 じ(12 じ)',  # 0 時の「じ」の部分
    clock_h:         '%{h} じ',      # 「じ」の部分(0 時以外)
    clock_only:      '%{h}',         # 「ふん」を問わないとき
    clock_hm:        '%{h} %{m} ふん',
    numbers:         nil,            # 数字はそのまま書く(英単語にしない)
    clock_min_oh:    nil,            # 1 桁のふんも数字をそのまま書く
    # --- ステージのサブタイトル ---
    subtitles: {
      'S1-1-1' => 'たしざん暗算1', 'S1-1-2' => 'たしざん暗算2', 'S1-1-3' => 'たしざん暗算3',
      'S1-1-4' => 'たしざん暗算4', 'S1-1-5' => 'たしざん暗算5',
      'S1-2-1' => 'ひきざん暗算1', 'S1-2-2' => 'ひきざん暗算2',
      'S1-3-1' => 'かけざん暗算1', 'S1-3-2' => 'かけざん暗算2', 'S1-3-3' => 'かけざん暗算3',
      'S1-3-4' => 'かけざん暗算4', 'S1-3-5' => 'かけざん暗算5', 'S1-3-6' => 'かけざん暗算6',
      'S1-5-1' => 'たしひき暗算1',
      'S1-8-1' => '小数かけざん暗算1',
      'S2-1-1' => 'たしざん筆算1', 'S2-1-2' => 'たしざん筆算2', 'S2-1-3' => 'たしざん筆算3',
      'S2-1-4' => 'たしざん筆算4', 'S2-1-5' => 'たしざん筆算5',
      'S2-2-1' => 'ひきざん筆算1', 'S2-2-2' => 'ひきざん筆算2', 'S2-2-3' => 'ひきざん筆算3',
      'S2-2-4' => 'ひきざん筆算4',
      'S3-1-1' => 'よみ1', 'S3-1-2' => 'よみ2', 'S3-1-3' => 'よみ3', 'S3-1-4' => 'よみ4'
    }.freeze,
    # --- 使い方(--help)---
    usage:          '使い方: ruby arithprac.rb [options]',
    opt_stage:      'ステージ名(例: S1-1-1)。--num/--pattern/--ratio を無視。',
    opt_pages:      "問題のページ数(1 ページ = 2 回分, 既定 #{DEFAULT_PAGES})",
    opt_stage_list: 'ステージ名とサブタイトルの一覧を表示して終了',
    opt_num:        "1 回あたりの問題数(暗算: #{MIN_PROBLEMS}〜#{MAX_PROBLEMS}, 既定 #{DEFAULT_PROBLEMS} / " \
                    "筆算・時計: #{REGION_SHAPES.keys.join('・')} のいずれか, 既定 #{DEFAULT_REGIONS}・" \
                    "#{DEFAULT_CLOCK_REGIONS})",
    opt_pattern:    'パターン名(例: P1-1-1)。複数指定可。--stage を無視。',
    opt_ratio:      'パターンの混合比率(--pattern と同数)。合計 1 に正規化。',
    opt_scale:      '文字・解答欄サイズ small/medium/large/onesmall(既定 small)。' \
                    'onesmall は暗算のみの 1 列レイアウト。時計では使わない。--stage 指定時は無視。',
    opt_output:     "出力ファイル名(.pdf)。不正な拡張子なら #{BASENAME}.pdf を使用。",
    opt_seed:       '乱数シード(再現用)',
    opt_lang:       "使用言語 #{LANGS.join('/')}(既定 #{DEFAULT_LANG})",
    opt_help:       'この使い方を表示',
    # --- 実行時のメッセージ ---
    seed_info:      'seed = %{seed}%{auto} で生成します。ページタグ: %{tag}',
    seed_auto:      '(自動生成)',
    info_kuku:      'ステージ %{key}(%{sub}): 九九固定 4 回・1 回 16 問(scale=%{scale}, CLI 指定は無視)。',
    info_stage:     'ステージ %{key}(%{sub}): %{pages} ページ・%{sets} 回・1 回 %{num} 問(%{desc})。',
    info_pattern:   'パターン %{list}: %{sets} 回・1 回 %{num} 問(%{desc})。',
    info_typ:       'Typst ファイルを生成: %{path}',
    info_pdf:       'PDF を生成: %{path}%{pages}',
    pages_suffix:   ' (全%{n}ページ)',
    warn_stage_opts:  '警告: --stage 指定時は --pattern/--ratio/--num は無視されます。',
    warn_stage_scale: '警告: --stage 指定時は --scale は無視されます(ステージ固有のスケールを使用)。',
    warn_clock_scale: '警告: 時計(P4-x-x)では --scale は使いません(時計盤はリージョンに合わせた大きさになります)。',
    warn_output_ext:  '警告: 出力拡張子が .pdf ではないため %{name} を使用します。',
    err_lang:         'エラー: --lang は %{list} のいずれかを指定してください(指定: %{v})。',
    err_pages:        'エラー: --pages は 1 以上を指定してください(指定: %{v})。',
    err_scale:        'エラー: --scale は %{list} のいずれかを指定してください(指定: %{v})。',
    err_scale_oneline: 'エラー: --scale %{scale}(1 列レイアウト)は暗算(P1-x-x/P3-x-x)のみで使用できます。',
    err_stage:        "エラー: ステージ '%{v}' は存在しません(一覧は --stage-list)。",
    err_pattern_unknown: 'エラー: パターンが存在しません: %{list}',
    err_pattern_forms:   'エラー: 暗算(P1-x-x/P3-x-x)・筆算(P2-x-x)・時計(P4-x-x)のパターンは同時に指定できません。',
    err_num_mental:   'エラー: 問題数は %{min}〜%{max} の範囲で指定してください(指定: %{v})。',
    err_num_region:   'エラー: 筆算・時計の問題数は %{shapes} のいずれかを指定してください(指定: %{v})。',
    err_ratio_count:  'エラー: --ratio は --pattern と同じ数だけ指定してください。',
    err_ratio_negative: 'エラー: --ratio に負の値は指定できません。',
    err_ratio_zero:   'エラー: --ratio の合計が 0 です。',
    err_no_mode:      'エラー: --stage または --pattern を指定してください(一覧は --stage-list)。',
    err_typst:        'typst のコンパイルに失敗しました。上の出力を確認してください。',
    err_stage_region: '内部エラー: ステージ %{key} の問題数(%{num})はリージョンに分割できません(%{shapes})。',
    err_dec_exp:      '内部エラー: 小数パターンの指数範囲 %{exps} が「1以上=%{ge1}」と矛盾します。',
    err_dec_empty:    '内部エラー: パターン %{key} を満たす数値の組がありません。'
  },
  en: {
    # --- 紙面(PDF)---
    title_mental: 'Mental Math Master',
    title_column: 'Written Calc Master',
    title_clock:  'Clock Master',
    name:         'Name',
    score:        'Pts',
    answers:      'Answers',
    ans_head_sep: ' - ', # 語の切れ目が分かるようにハイフンで区切る
    set_no:       'Set %{n}',
    # 時計(よみ)の解答は数字ではなく英単語で書く(例: 3 時 15 分 → three fifteen)。
    # 解答欄には「It is」(左)と「．」(右)を置き、単位は書かない。
    # 英語には「0 時」の読みが無いため、0 じ は 12 として書く(併記もしない)。
    clock_itis:      'It is',
    clock_period:    '．',
    clock_h0:        'twelve',       # 0 時の「じ」の部分
    clock_h:         '%{h}',         # 「じ」の部分(0 時以外)
    clock_only:      "%{h} o'clock", # 「ふん」を問わないとき
    clock_hm:        '%{h} %{m}',
    numbers:         EN_NUMBERS,     # 数字は英単語で書く
    clock_min_oh:    'oh %{m}',      # 1 桁のふん(例: 3 じ 5 ふん → three oh five)
    # --- ステージのサブタイトル ---
    # 紙面の見出し行に収める必要があるため、長くなりすぎないようにする。
    subtitles: {
      'S1-1-1' => 'Mental Add 1', 'S1-1-2' => 'Mental Add 2', 'S1-1-3' => 'Mental Add 3',
      'S1-1-4' => 'Mental Add 4', 'S1-1-5' => 'Mental Add 5',
      'S1-2-1' => 'Mental Sub 1', 'S1-2-2' => 'Mental Sub 2',
      'S1-3-1' => 'Mental Mul 1', 'S1-3-2' => 'Mental Mul 2', 'S1-3-3' => 'Mental Mul 3',
      'S1-3-4' => 'Mental Mul 4', 'S1-3-5' => 'Mental Mul 5', 'S1-3-6' => 'Mental Mul 6',
      'S1-5-1' => 'Mental Add & Sub 1',
      'S1-8-1' => 'Mental Decimal Mul 1',
      'S2-1-1' => 'Column Add 1', 'S2-1-2' => 'Column Add 2', 'S2-1-3' => 'Column Add 3',
      'S2-1-4' => 'Column Add 4', 'S2-1-5' => 'Column Add 5',
      'S2-2-1' => 'Column Sub 1', 'S2-2-2' => 'Column Sub 2', 'S2-2-3' => 'Column Sub 3',
      'S2-2-4' => 'Column Sub 4',
      'S3-1-1' => 'Clock Reading 1', 'S3-1-2' => 'Clock Reading 2',
      'S3-1-3' => 'Clock Reading 3', 'S3-1-4' => 'Clock Reading 4'
    }.freeze,
    # --- 使い方(--help)---
    usage:          'Usage: ruby arithprac.rb [options]',
    opt_stage:      'Stage name (e.g. S1-1-1). Ignores --num/--pattern/--ratio.',
    opt_pages:      "Pages of problems (1 page = 2 sets, default #{DEFAULT_PAGES})",
    opt_stage_list: 'List stage names with their subtitles and exit',
    opt_num:        "Problems per set (mental: #{MIN_PROBLEMS}-#{MAX_PROBLEMS}, default #{DEFAULT_PROBLEMS} / " \
                    "column and clock: one of #{REGION_SHAPES.keys.join(', ')}, default #{DEFAULT_REGIONS} and " \
                    "#{DEFAULT_CLOCK_REGIONS})",
    opt_pattern:    'Pattern name (e.g. P1-1-1). Repeatable. Ignores --stage.',
    opt_ratio:      'Mix ratio of the patterns (as many as --pattern). Normalized to sum 1.',
    opt_scale:      'Text and answer box size: small/medium/large/onesmall (default small). ' \
                    'onesmall is the one-column layout for mental only; not used for clock. Ignored with --stage.',
    opt_output:     "Output file name (.pdf). #{BASENAME}.pdf is used for any other extension.",
    opt_seed:       'Random seed (for reproducible output)',
    opt_lang:       "Language #{LANGS.join('/')} (default #{DEFAULT_LANG})",
    opt_help:       'Show this help',
    # --- 実行時のメッセージ ---
    seed_info:      'Generating with seed = %{seed}%{auto}. Page tag: %{tag}',
    seed_auto:      ' (auto-generated)',
    info_kuku:      'Stage %{key} (%{sub}): fixed times tables, 4 sets of 16 problems ' \
                    '(scale=%{scale}, CLI options ignored).',
    info_stage:     'Stage %{key} (%{sub}): %{pages} pages, %{sets} sets, %{num} problems per set (%{desc}).',
    info_pattern:   'Patterns %{list}: %{sets} sets, %{num} problems per set (%{desc}).',
    info_typ:       'Typst file written: %{path}',
    info_pdf:       'PDF written: %{path}%{pages}',
    pages_suffix:   ' (%{n} pages)',
    warn_stage_opts:  'Warning: --pattern/--ratio/--num are ignored when --stage is given.',
    warn_stage_scale: 'Warning: --scale is ignored when --stage is given (the scale of the stage is used).',
    warn_clock_scale: 'Warning: --scale is not used for clock patterns (P4-x-x); ' \
                      'the clock face is sized to fit its region.',
    warn_output_ext:  'Warning: the output extension is not .pdf, so %{name} is used.',
    err_lang:         'Error: --lang must be one of %{list} (given: %{v}).',
    err_pages:        'Error: --pages must be 1 or greater (given: %{v}).',
    err_scale:        'Error: --scale must be one of %{list} (given: %{v}).',
    err_scale_oneline: 'Error: --scale %{scale} (one-column layout) can be used only for mental patterns ' \
                       '(P1-x-x/P3-x-x).',
    err_stage:        "Error: stage '%{v}' does not exist (see --stage-list).",
    err_pattern_unknown: 'Error: no such pattern: %{list}',
    err_pattern_forms:   'Error: mental (P1-x-x/P3-x-x), column (P2-x-x) and clock (P4-x-x) patterns ' \
                         'cannot be given together.',
    err_num_mental:   'Error: the number of problems must be between %{min} and %{max} (given: %{v}).',
    err_num_region:   'Error: the number of problems for column and clock must be one of %{shapes} (given: %{v}).',
    err_ratio_count:  'Error: --ratio must be given as many times as --pattern.',
    err_ratio_negative: 'Error: --ratio must not be negative.',
    err_ratio_zero:   'Error: the sum of --ratio is 0.',
    err_no_mode:      'Error: give --stage or --pattern (see --stage-list).',
    err_typst:        'typst failed to compile. See the output above.',
    err_stage_region: 'Internal error: the number of problems of stage %{key} (%{num}) cannot be split ' \
                      'into regions (%{shapes}).',
    err_dec_exp:      'Internal error: exponent range %{exps} of the decimal pattern contradicts ' \
                      '"1 or greater = %{ge1}".',
    err_dec_empty:    'Internal error: no pair of numbers satisfies pattern %{key}.'
  }
}.freeze

# ---- パターン定義 ------------------------------------------------------
# 各パターンは op(:add/:sub/:mul/:read)と、[a, b] を返す生成 proc を持つ。
# 制約(桁範囲・繰り上がり・0/1 の出現など)は棄却サンプリングで満たす。
# form は出題形式。P1-x-x/P3-x-x は暗算(:mental)、P2-x-x は筆算(:column)、
# P4-x-x は時計(:clock)。
PATTERNS = {}

# attrs はパターン固有の属性(時計の minute など)。問題の生成時に参照する。
def def_pattern(id, op, **attrs, &gen)
  form = case id.upcase
         when /\AP2/ then :column  # 筆算
         when /\AP4/ then :clock   # 時計
         else :mental              # 暗算
         end
  PATTERNS[id.upcase] = { id: id, op: op, form: form, gen: gen }.merge(attrs)
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

# --- 暗算-小数乗算(P3-3-x)---
# 小数は「浮動小数点表記」の (仮数部, 指数部) と等価な (m, k) の対で扱う。
#   値 = m * 10**k。m は末尾に 0 を持たない整数(末尾の 0 は仮数部桁数を減らすため)。
#   仮数部桁数 = m の桁数、指数部 = k + 仮数部桁数 - 1。
#   例: 0.015 → m=15, k=-3(仮数部 1.5・仮数部桁数 2・指数部 -2)
# 「ゼロ発生」= 積 m1*m2 の下位に出る 0。その桁数(ゼロ発生桁数)だけ仮数部桁数が減る。
#   例: 0.15 × 0.6 → 15*6 = 90(ゼロ発生 1 桁)→ m=9, k=-2 → 0.09

# 指数部の範囲。CLAUDE.md の「-1～-3」のように 0 に近い側から書けるようにする。
def exp_range(from, to)
  from <= to ? (from..to).to_a : (to..from).to_a
end

# 被乗数・乗数の仕様 [1以上か, 仮数部桁数, 指数部の範囲]。lt1 = 1未満、gte1 = 1以上。
def lt1(digits, from, to)  = [false, digits, exp_range(from, to)]
def gte1(digits, from, to) = [true,  digits, exp_range(from, to)]

# 結果の仕様 [1以上か, 仮数部桁数, ゼロ発生桁数, 指数部の範囲]。
def rlt1(digits, zeros, from, to)  = [false, digits, zeros, exp_range(from, to)]
def rgte1(digits, zeros, from, to) = [true,  digits, zeros, exp_range(from, to)]

# 仮数部桁数 digits の仮数(m)の候補。末尾の 0 は仮数部桁数を減らすため除く。
# 桁数 1 では仮数 1(0.1 / 1 / 10 など)を除く(パターン共通の制約)。
def dec_mantissas(digits)
  digits == 1 ? (2..9).to_a : (11..99).reject { |m| (m % 10).zero? }
end

# 値(m * 10**k)。整数になる場合は Integer にして整数の問題と同じ扱いにする。
def dec_value(m, k)
  v = Rational(m) * Rational(10)**k
  v.denominator == 1 ? v.numerator : v
end

# 固定小数点表記の文字列。整数はそのまま、小数は必要な桁数だけ書く(例: 0.000002)。
# 積は Rational(4800/1) のように「整数値の Rational」になりうるので Rational に
# 統一して判定する(Integer とみなせるなら小数点を付けない)。
def dec_str(v)
  r = Rational(v)
  return r.numerator.to_s if r.denominator == 1

  nd = 0
  nd += 1 while (r * 10**nd).denominator != 1
  s = (r * 10**nd).to_i.to_s.rjust(nd + 1, '0')
  "#{s[0...-nd]}.#{s[-nd..]}"
end

# (m1,k1) × (m2,k2) の積を正規化して [m, k, ゼロ発生桁数] を返す。
def dec_mul(m1, k1, m2, k2)
  raw = m1 * m2
  zeros = 0
  zeros += 1 while (raw % 10**(zeros + 1)).zero?
  [raw / 10**zeros, k1 + k2 + zeros, zeros]
end

# 被乗数・乗数の候補 [[m, k], ...]。
def dec_operands(spec)
  ge1, digits, exps = spec
  unless exps.all? { |e| (e >= 0) == ge1 }
    raise t(:err_dec_exp, exps: exps.inspect, ge1: ge1)
  end

  exps.flat_map { |e| dec_mantissas(digits).map { |m| [m, e - (digits - 1)] } }
end

# パターンを満たす [被乗数, 乗数] の全候補。桁数・ゼロ発生桁数・指数の条件が厳しく
# 棄却サンプリングでは効率が悪いため、候補を列挙して等確率で選ぶ。
def dec_candidates(aspec, bspec, rspec)
  r_ge1, r_digits, r_zeros, r_exps = rspec
  dec_operands(aspec).product(dec_operands(bspec)).filter_map do |(m1, k1), (m2, k2)|
    m, k, zeros = dec_mul(m1, k1, m2, k2)
    next unless zeros == r_zeros && m.to_s.size == r_digits

    exp = k + r_digits - 1
    next unless r_exps.include?(exp) && (exp >= 0) == r_ge1

    [dec_value(m1, k1), dec_value(m2, k2)]
  end
end

# パターンごとの候補(初回使用時に列挙して覚える。全 75 パターンを起動時に
# 列挙すると 0.3 秒ほどかかるため、使うパターンだけ列挙する)。
DEC_CANDS = {}

# 小数乗算パターンを定義する。
#   a:, b: 被乗数・乗数の仕様(lt1 / gte1)
#   r:     結果の仕様(rlt1 / rgte1)
def def_dec_pattern(id, a:, b:, r:)
  key = id.upcase
  def_pattern(id, :mul) do
    cands = (DEC_CANDS[key] ||= dec_candidates(a, b, r))
    raise t(:err_dec_empty, key: key) if cands.empty?

    cands.sample
  end
end

# (1桁, 1桁, 1桁)
def_dec_pattern('P3-3-1',  a: lt1(1, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(1, 0, -2, -6))
def_dec_pattern('P3-3-2',  a: gte1(1, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(1, 0, 0, 3))
def_dec_pattern('P3-3-3',  a: gte1(1, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(1, 0, -1, -3))
def_dec_pattern('P3-3-4',  a: lt1(1, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(1, 0, 0, 3))
def_dec_pattern('P3-3-5',  a: lt1(1, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(1, 0, -1, -3))
def_dec_pattern('P3-3-6',  a: lt1(1, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(1, 1, -1, -5))
def_dec_pattern('P3-3-7',  a: gte1(1, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(1, 1, 0, 4))
def_dec_pattern('P3-3-8',  a: gte1(1, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(1, 1, -1, -2))
def_dec_pattern('P3-3-9',  a: lt1(1, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(1, 1, 0, 4))
def_dec_pattern('P3-3-10', a: lt1(1, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(1, 1, -1, -2))

# (1桁, 1桁, 2桁)
def_dec_pattern('P3-3-11', a: lt1(1, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(2, 0, -1, -5))
def_dec_pattern('P3-3-12', a: gte1(1, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(2, 0, 0, 4))
def_dec_pattern('P3-3-13', a: gte1(1, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(2, 0, -1, -2))
def_dec_pattern('P3-3-14', a: lt1(1, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(2, 0, 0, 4))
def_dec_pattern('P3-3-15', a: lt1(1, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(2, 0, -1, -2))

# (1桁or2桁, 2桁or1桁, 2〜3桁・ゼロ発生なし)
def_dec_pattern('P3-3-16', a: lt1(2, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(2, 0, -2, -6))
def_dec_pattern('P3-3-17', a: lt1(2, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(3, 0, -1, -5))
def_dec_pattern('P3-3-18', a: lt1(1, -1, -3),  b: lt1(2, -1, -3),  r: rlt1(2, 0, -2, -6))
def_dec_pattern('P3-3-19', a: lt1(1, -1, -3),  b: lt1(2, -1, -3),  r: rlt1(3, 0, -1, -5))

# 指数 0 かつ 仮数部桁数 2 は「1以上 && 小数点以下の桁あり」(例: 1.4)を意味する。
def_dec_pattern('P3-3-20', a: gte1(2, 0, 0),   b: gte1(1, 0, 4),   r: rgte1(2, 0, 0, 4))
def_dec_pattern('P3-3-21', a: gte1(1, 0, 4),   b: gte1(2, 0, 0),   r: rgte1(2, 0, 0, 4))
def_dec_pattern('P3-3-22', a: gte1(2, 0, 0),   b: gte1(1, 0, 4),   r: rgte1(3, 0, 1, 5))
def_dec_pattern('P3-3-23', a: gte1(1, 0, 4),   b: gte1(2, 0, 0),   r: rgte1(3, 0, 1, 5))

def_dec_pattern('P3-3-24', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(2, 0, 0, 3))
def_dec_pattern('P3-3-25', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rgte1(2, 0, 0, 3))
def_dec_pattern('P3-3-26', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(3, 0, 0, 4))
def_dec_pattern('P3-3-27', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rgte1(3, 0, 0, 4))

def_dec_pattern('P3-3-28', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(2, 0, -1, -3))
def_dec_pattern('P3-3-29', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rlt1(2, 0, -1, -3))
def_dec_pattern('P3-3-30', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(3, 0, -1, -2))
def_dec_pattern('P3-3-31', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rlt1(3, 0, -1, -2))

def_dec_pattern('P3-3-32', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(2, 0, 0, 3))
def_dec_pattern('P3-3-33', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rgte1(2, 0, 0, 3))
def_dec_pattern('P3-3-34', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(3, 0, 0, 4))
def_dec_pattern('P3-3-35', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rgte1(3, 0, 0, 4))

def_dec_pattern('P3-3-36', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(2, 0, -1, -3))
def_dec_pattern('P3-3-37', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rlt1(2, 0, -1, -3))
def_dec_pattern('P3-3-38', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(3, 0, -1, -2))
def_dec_pattern('P3-3-39', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rlt1(3, 0, -1, -2))

# (1桁or2桁, 2桁or1桁, 1〜2桁・ゼロ発生あり)
def_dec_pattern('P3-3-40', a: lt1(2, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(1, 1, -2, -6))
def_dec_pattern('P3-3-41', a: lt1(2, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(2, 1, -1, -5))
def_dec_pattern('P3-3-42', a: lt1(1, -1, -3),  b: lt1(2, -1, -3),  r: rlt1(1, 1, -2, -6))
def_dec_pattern('P3-3-43', a: lt1(1, -1, -3),  b: lt1(2, -1, -3),  r: rlt1(2, 1, -1, -5))
def_dec_pattern('P3-3-44', a: lt1(2, -1, -3),  b: lt1(1, -1, -3),  r: rlt1(1, 2, -1, -5))
def_dec_pattern('P3-3-45', a: lt1(1, -1, -3),  b: lt1(2, -1, -3),  r: rlt1(1, 2, -1, -5))

def_dec_pattern('P3-3-46', a: gte1(2, 0, 0),   b: gte1(1, 0, 4),   r: rgte1(1, 1, 0, 4))
def_dec_pattern('P3-3-47', a: gte1(1, 0, 4),   b: gte1(2, 0, 0),   r: rgte1(1, 1, 0, 4))
def_dec_pattern('P3-3-48', a: gte1(2, 0, 0),   b: gte1(1, 0, 4),   r: rgte1(1, 2, 1, 4))
def_dec_pattern('P3-3-49', a: gte1(1, 0, 4),   b: gte1(2, 0, 0),   r: rgte1(1, 2, 1, 4))
def_dec_pattern('P3-3-50', a: gte1(2, 0, 0),   b: gte1(1, 0, 4),   r: rgte1(2, 1, 1, 4))
def_dec_pattern('P3-3-51', a: gte1(1, 0, 4),   b: gte1(2, 0, 0),   r: rgte1(2, 1, 1, 4))

def_dec_pattern('P3-3-52', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(1, 1, 0, 3))
def_dec_pattern('P3-3-53', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rgte1(1, 1, 0, 3))
def_dec_pattern('P3-3-54', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(2, 1, 0, 4))
def_dec_pattern('P3-3-55', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rgte1(2, 1, 0, 4))
def_dec_pattern('P3-3-56', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rgte1(1, 2, 0, 4))
def_dec_pattern('P3-3-57', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rgte1(1, 2, 0, 4))

def_dec_pattern('P3-3-58', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(1, 1, -1, -3))
def_dec_pattern('P3-3-59', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rlt1(1, 1, -1, -3))
def_dec_pattern('P3-3-60', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(2, 1, -1, -2))
def_dec_pattern('P3-3-61', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rlt1(2, 1, -1, -2))
def_dec_pattern('P3-3-62', a: gte1(2, 0, 4),   b: lt1(1, -1, -3),  r: rlt1(1, 2, -1, -2))
def_dec_pattern('P3-3-63', a: gte1(1, 0, 4),   b: lt1(2, -1, -3),  r: rlt1(1, 2, -1, -2))

def_dec_pattern('P3-3-64', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(1, 1, 0, 3))
def_dec_pattern('P3-3-65', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rgte1(1, 1, 0, 3))
def_dec_pattern('P3-3-66', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(2, 1, 0, 4))
def_dec_pattern('P3-3-67', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rgte1(2, 1, 0, 4))
def_dec_pattern('P3-3-68', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rgte1(1, 2, 0, 4))
def_dec_pattern('P3-3-69', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rgte1(1, 2, 0, 4))

def_dec_pattern('P3-3-70', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(1, 1, -1, -3))
def_dec_pattern('P3-3-71', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rlt1(1, 1, -1, -3))
def_dec_pattern('P3-3-72', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(2, 1, -1, -2))
def_dec_pattern('P3-3-73', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rlt1(2, 1, -1, -2))
def_dec_pattern('P3-3-74', a: lt1(2, -1, -3),  b: gte1(1, 0, 4),   r: rlt1(1, 2, -1, -2))
def_dec_pattern('P3-3-75', a: lt1(1, -1, -3),  b: gte1(2, 0, 4),   r: rlt1(1, 2, -1, -2))

# 小数乗算のパターン名の配列。dec_pats(1..5) → %w[P3-3-1 P3-3-2 P3-3-3 P3-3-4 P3-3-5]
def dec_pats(*nums)
  nums.flat_map { |n| Array(n) }.map { |n| "P3-3-#{n}" }
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

# --- 筆算-減算(P2-2-x)---
# 「○の位の繰り下がり」= ○の位の数値を 1 つ減らして 1 つ下の位を 10 増やす操作。
# 例: 67 - 8 は一の位が 7 < 8 なので「十の位の繰り下がりあり」。
# sub_borrows(a, b) は下の位から順に [十の位, 百の位, 千の位] の繰り下がりの
# 有無を返す(i 桁目の計算で下位からの借りを含めて引けなければ、その 1 つ上の位で
# 繰り下がりが起きる)。
def sub_borrows(a, b)
  carry = false
  (0..2).map do |i|
    d = 10**i
    carry = a / d % 10 < b / d % 10 + (carry ? 1 : 0)
  end
end

def_pattern('P2-2-1', :sub) do   # 2桁 - 1桁 = 2桁(繰り下がりなし)
  loop { a = rand(10..99); b = rand(1..9); break [a, b] if a % 10 >= b }
end
def_pattern('P2-2-2', :sub) do   # 2桁 - 1桁 = 2桁(十の位の繰り下がりあり)
  # 繰り下がりで十の位が 1 減るため、結果を 2 桁に保つには a >= 20 が要る。
  loop { a = rand(20..99); b = rand(1..9); break [a, b] if a % 10 < b }
end
def_pattern('P2-2-3', :sub) do   # 3桁 - 2桁 = 3桁(百・十の位の繰り下がりなし)
  loop do
    a = rand(100..999); b = rand(10..99)
    br = sub_borrows(a, b)
    break [a, b] if !br[0] && !br[1]
  end
end
def_pattern('P2-2-4', :sub) do   # 3桁 - 2桁 = 3桁(百の位なし・十の位あり)
  loop do
    a = rand(100..999); b = rand(10..99)
    br = sub_borrows(a, b)
    break [a, b] if br[0] && !br[1]
  end
end
def_pattern('P2-2-5', :sub) do   # 3桁 - 2桁 = 2桁(百の位あり・十の位なし)
  # 結果が 2 桁 = 百の位の繰り下がりで百の位が 0 になる、すなわち被減数は 100..199。
  loop do
    a = rand(100..199); b = rand(10..99)
    br = sub_borrows(a, b)
    break [a, b] if !br[0] && br[1]
  end
end
def_pattern('P2-2-6', :sub) do   # 3桁 - 2桁 = 2桁(百・十の位の繰り下がりあり)
  loop do
    a = rand(100..199); b = rand(10..99)
    br = sub_borrows(a, b)
    break [a, b] if br[0] && br[1] && a - b >= 10
  end
end
def_pattern('P2-2-7', :sub) do   # 3桁 - 3桁 = 3桁(百・十の位の繰り下がりなし)
  loop do
    a = rand(100..999); b = rand(100..999)
    br = sub_borrows(a, b)
    break [a, b] if !br[0] && !br[1] && a - b >= 100
  end
end
def_pattern('P2-2-8', :sub) do   # 3桁 - 3桁 = 3桁(百の位なし・十の位あり)
  loop do
    a = rand(100..999); b = rand(100..999)
    br = sub_borrows(a, b)
    break [a, b] if br[0] && !br[1] && a - b >= 100
  end
end
def_pattern('P2-2-9', :sub) do   # 3桁 - 3桁 = 2〜3桁(百の位あり・十の位なし)
  loop do
    a = rand(100..999); b = rand(100..999)
    br = sub_borrows(a, b)
    break [a, b] if !br[0] && br[1] && a - b >= 10
  end
end
def_pattern('P2-2-10', :sub) do  # 3桁(下 2 桁 ≠ 00) - 3桁 = 2〜3桁(百・十の位あり)
  loop do
    a = rand(100..999); b = rand(100..999)
    next if (a % 100).zero?

    br = sub_borrows(a, b)
    break [a, b] if br[0] && br[1] && a - b >= 10
  end
end
def_pattern('P2-2-11', :sub) do  # 3桁(下 2 桁 = 00) - 3桁 = 2〜3桁(百・十の位あり)
  # 被減数が X00 なら一の位で必ず借りが要る(減数の一の位が 0 でなければ)。
  # 100 では 2 桁以上の結果を作れない(減数も 3 桁のため)ので 200 以上とする。
  loop do
    a = rand(2..9) * 100; b = rand(100..999)
    br = sub_borrows(a, b)
    break [a, b] if br[0] && br[1] && a - b >= 10
  end
end
def_pattern('P2-2-12', :sub) do  # 4桁 - 3〜4桁 = 4桁(千の位の繰り下がりなし)
  loop do
    a = rand(1000..9999); b = rand(100..9999)
    break [a, b] if !sub_borrows(a, b)[2] && a - b >= 1000
  end
end
def_pattern('P2-2-13', :sub) do  # 4桁 - 3〜4桁 = 3〜4桁(千の位の繰り下がりあり)
  loop do
    a = rand(1000..9999); b = rand(100..9999)
    break [a, b] if sub_borrows(a, b)[2] && a - b >= 100
  end
end
def_pattern('P2-2-14', :sub) do  # 4桁(下 3 桁 ≠ 000) - 3〜4桁 = 3〜4桁(千・百・十の位あり)
  loop do
    a = rand(1000..9999); b = rand(100..9999)
    next if (a % 1000).zero?

    break [a, b] if sub_borrows(a, b).all? && a - b >= 100
  end
end
def_pattern('P2-2-15', :sub) do  # 4桁(下 3 桁 = 000) - 2〜4桁 = 2〜4桁(千・百・十の位あり)
  # 被減数が X000 なら、減数の一の位が 0 でない限り 3 つの位すべてで繰り下がる。
  loop do
    a = rand(1..9) * 1000; b = rand(10..9999)
    break [a, b] if sub_borrows(a, b).all? && a - b >= 10
  end
end

# --- 時計-よみ(P4-1-x)---
# 時計(よみ)は a を「じ」(0..11)、b を「ふん」(0..59)として扱う。
# minute が偽のパターン(P4-1-1)は「ふん」を問わない(解答欄にも「ふん」を出さない)。

# パターンごとの「ふん」の候補。
CLOCK_MINUTES = {
  'P4-1-1' => [0],
  'P4-1-2' => [15, 30, 45],
  'P4-1-3' => [5, 10, 20, 25, 35, 40, 50, 55],
  'P4-1-4' => (1..59).reject { |m| (m % 5).zero? }.freeze
}.freeze

# 時計(よみ)のパターンを定義する。minute: 偽なら「ふん」を問わない。
def def_clock_pattern(id, minute: true)
  mins = CLOCK_MINUTES[id.upcase]
  def_pattern(id, :read, minute: minute) { [rand(12), mins.sample] }
end

def_clock_pattern('P4-1-1', minute: false)
def_clock_pattern('P4-1-2')
def_clock_pattern('P4-1-3')
def_clock_pattern('P4-1-4')

# 時計(よみ)の解答文字列。「じ」「ふん」の書き方と 0 時の扱いは言語ごとに異なる
# (日本語は「0 じ(12 じ)」と併記、英語は 12 とのみ書く)ため TEXTS 側で決める。
def clock_answer(hour, minute, minute_asked)
  h = hour.zero? ? t(:clock_h0) : t(:clock_h, h: clock_num(hour))
  minute_asked ? t(:clock_hm, h: h, m: clock_min_num(minute)) : t(:clock_only, h: h)
end

# ---- 制約(コスト関数)---------------------------------------------------
# 1 回内で「総コストを上限以下に保つ」ための各問コスト関数。
# adjust! がコストの正の問題を差し替えて総コストを調整する(下記参照)。
COST_ONES     = ->(p) { ones_in(p) }              # 被演算数(a,b)に現れる '1' の個数
COST_B_ONES   = ->(p) { p[:b].to_s.count('1') }   # 減数(b)に現れる '1' の個数
# 加減混在ステージ用。加算なら被加数・加数、減算なら減数(b)に現れる '1' の個数。
# 被減数は別途 COST_A_TEN で 10 の出現を抑えるため、ここでは数えない。
COST_MIXED_ONES = ->(p) { p[:op] == :add ? ones_in(p) : p[:b].to_s.count('1') }
COST_ZERO_ANS = ->(p) { p[:ans].zero? ? 1 : 0 }   # 答えが 0 なら 1
COST_ZERO_TEN_ANS = ->(p) { [0, 10].include?(p[:ans]) ? 1 : 0 } # 答えが 0 または 10 なら 1
# 加減混在ステージ用。ひきざんで答えが 0 または 10 なら 1(たしざんは数えない)。
COST_SUB_ZERO_TEN_ANS = ->(p) { p[:op] == :sub && [0, 10].include?(p[:ans]) ? 1 : 0 }
COST_A_TEN    = ->(p) { p[:a] == 10 ? 1 : 0 }     # 被減数(a)が 10 なら 1
# 第 1 項・第 2 項(被加数と加数 / 被減数と減数)の一の位に現れる '0' と '1' の個数(0〜2)
COST_UNITS_ZERO_ONE = ->(p) { [p[:a] % 10, p[:b] % 10].count { |d| [0, 1].include?(d) } }
# 第 1 項(被加数・被減数)の十の位が '1' なら 1
COST_A_TENS_ONE = ->(p) { p[:a] / 10 % 10 == 1 ? 1 : 0 }
# 第 1 項(被加数・被減数)の十の位が '0' または '1' なら 1
COST_A_TENS_ZERO_ONE = ->(p) { [0, 1].include?(p[:a] / 10 % 10) ? 1 : 0 }
# 第 1 項・第 2 項の十の位に現れる '0' と '1' の個数(0〜2)
COST_TENS_ZERO_ONE = ->(p) { [p[:a] / 10 % 10, p[:b] / 10 % 10].count { |d| [0, 1].include?(d) } }
# 1 問の中で被演算数どうしが似すぎなら 1。同じ桁数で相違する桁が 1 つ以下
# (649 + 639 や 136 + 136、345 - 341 など)を「似すぎ」とする。桁数が違えば似ていない。
# 1 桁どうしは必ず相違 1 桁以下になるため、2 桁以上のみを対象とする。
COST_SIMILAR_AB = lambda do |p|
  sa = p[:a].to_s
  sb = p[:b].to_s
  next 0 unless sa.size == sb.size && sa.size >= 2

  sa.chars.zip(sb.chars).count { |x, y| x != y } <= 1 ? 1 : 0
end

# 減数(b)の一の位が '1' なら 1
COST_B_UNITS_ONE = ->(p) { p[:b] % 10 == 1 ? 1 : 0 }
# 減数(b)の十の位(2 桁以上のときのみ)と一の位に現れる '0' の個数(0〜2)
COST_B_LOW_ZERO = ->(p) { p[:b].to_s.chars.last(2).count('0') }
# 答えの一の位が '0' または '1' なら 1
COST_ANS_UNITS_ZERO_ONE = ->(p) { [0, 1].include?(p[:ans] % 10) ? 1 : 0 }
# 答えの一の位が '0' なら 1
COST_ANS_UNITS_ZERO = ->(p) { (p[:ans] % 10).zero? ? 1 : 0 }
# (第 1 項の一の位, 第 2 項の一の位) の組。1 回内での重複を見るための鍵。
UNITS_PAIR = ->(p) { [p[:a] % 10, p[:b] % 10] }
# (第 1 項の下 2 桁, 第 2 項の下 2 桁) の組。同上(3 桁以上の問題向け)。
LOW2_PAIR  = ->(p) { [p[:a] % 100, p[:b] % 100] }

# 鍵 key の値が 1 回内で重複したときに正となるコスト関数を作る。1 回(set)全体を
# 見る形式(引数 2 つ)。組が重複したとき、後から出たほう(n が大きいほう)に 1 を
# 付ける。上限 0 なら「組は 1 回内で 1 度きり」になる。回に属さない候補(n が無い)
# は、組が一致する問題があれば正になるため、gen_zero_cost は「まだ使われていない
# 組」の問題を選ぶことになる。
def dup_cost(key)
  lambda do |p, set|
    set.count do |q|
      q[:n] != p[:n] && key.call(q) == key.call(p) && (p[:n].nil? || q[:n] < p[:n])
    end
  end
end

COST_DUP_UNITS_PAIR = dup_cost(UNITS_PAIR)
COST_DUP_LOW2_PAIR  = dup_cost(LOW2_PAIR)

# 筆算ステージの制約セット。1 問内で 2 つの被演算数が似すぎるのを禁止(上限 0)
# するのと、一の位の '0'/'1' は 1 回までが共通。十の位の条件だけがステージの
# 進行につれて広がる。
CONSTR_SIMILAR         = [[COST_SIMILAR_AB, 0]].freeze
CONSTR_A_TENS_ONE      = (CONSTR_SIMILAR + [[COST_UNITS_ZERO_ONE, 1], [COST_A_TENS_ONE, 2]]).freeze
CONSTR_A_TENS_ZERO_ONE = (CONSTR_SIMILAR + [[COST_UNITS_ZERO_ONE, 1], [COST_A_TENS_ZERO_ONE, 2]]).freeze
CONSTR_TENS_ZERO_ONE   = (CONSTR_SIMILAR + [[COST_UNITS_ZERO_ONE, 1], [COST_TENS_ZERO_ONE, 2]]).freeze

# 筆算-減算ステージの制約セット。減数の一の位の '1'、被減数の十の位の '1'、
# 答えの一の位の '0'/'1' をそれぞれ 1 回までに抑え、(被減数の一の位, 減数の一の位)
# の組が 1 回内で重複しないようにする。
CONSTR_SUB_UNITS = (CONSTR_SIMILAR + [[COST_B_UNITS_ONE, 1], [COST_A_TENS_ONE, 1],
                                      [COST_ANS_UNITS_ZERO_ONE, 1],
                                      [COST_DUP_UNITS_PAIR, 0]]).freeze

# 同・3 桁以上を扱うステージ用。減数の下 2 桁の '0' と答えの一の位の '0' を
# それぞれ 1 回までに抑え、(被減数の下 2 桁, 減数の下 2 桁) の組の重複を禁じる。
CONSTR_SUB_LOW2 = (CONSTR_SIMILAR + [[COST_B_LOW_ZERO, 1], [COST_ANS_UNITS_ZERO, 1],
                                     [COST_DUP_LOW2_PAIR, 0]]).freeze

# 時計ステージの制約セット。1 回内で「じ」「ふん」がそれぞれ重複しないようにする
# (「ふん」が違っても同じ「じ」は出さない、およびその逆)。
CONSTR_CLOCK = [[dup_cost(->(p) { p[:a] }), 0], [dup_cost(->(p) { p[:b] }), 0]].freeze

# ---- ステージ定義 ------------------------------------------------------
# サブタイトル(たしざん暗算1 など)は言語依存のため TEXTS 側に置く(stage_subtitle)。
# entries: [[パターン候補配列, 問題数], ...]。候補が複数なら等確率で 1 つ選ぶ。
# constraints: [[コスト関数, 上限], ...]。1 回内で総コストを上限以下に調整する。
# special: :kuku のステージは問題数・並び順・回数が固定(CLI 指定を無視)。
STAGES = {
  'S1-1-1' => { scale: :large, constraints: [[COST_ONES, 2]],
                entries: [[%w[P1-1-1], 10]] },
  'S1-1-2' => { scale: :large, constraints: [[COST_ONES, 1]],
                entries: [[%w[P1-1-1], 2], [%w[P1-1-2], 2], [%w[P1-1-3], 6]] },
  'S1-1-3' => { scale: :large, constraints: [[COST_ONES, 1]],
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 8]] },
  'S1-1-4' => { scale: :large,
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 3], [%w[P1-1-5], 5]] },
  'S1-1-5' => { scale: :large,
                entries: [[%w[P1-1-3], 2], [%w[P1-1-6], 8]] },
  'S1-2-1' => { scale: :large,
                constraints: [[COST_B_ONES, 1], [COST_A_TEN, 2], [COST_ZERO_ANS, 1]],
                entries: [[%w[P1-2-1], 10]] },
  'S1-2-2' => { scale: :large,
                constraints: [[COST_B_ONES, 1], [COST_ZERO_TEN_ANS, 1]],
                entries: [[%w[P1-2-1], 2], [%w[P1-2-2], 8]] },
  'S1-3-1' => { scale: :medium, special: :kuku },
  'S1-3-2' => { scale: :medium, entries: [[%w[P1-3-1], 16]] },
  'S1-3-3' => { scale: :small, entries: [[%w[P1-3-2], 20]] },
  'S1-3-4' => { scale: :small, entries: [[%w[P1-3-3], 20]] },
  'S1-3-5' => { scale: :small, entries: [[%w[P1-3-4], 20]] },
  'S1-3-6' => { scale: :small, entries: [[%w[P1-3-5], 10], [%w[P1-3-6], 10]] },
  'S1-5-1' => { scale: :large,
                constraints: [[COST_MIXED_ONES, 1], [COST_A_TEN, 1], [COST_SUB_ZERO_TEN_ANS, 1]],
                entries: [[%w[P1-1-3], 2], [%w[P1-1-6], 3],
                          [%w[P1-2-1], 2], [%w[P1-2-2], 3]] },
  'S1-8-1' => { scale: :onesmall,
                entries: [[dec_pats(1..5), 1], [dec_pats(6..10), 1], [dec_pats(11..15), 1],
                          [dec_pats(16..19), 1], [dec_pats(20..23), 1], [dec_pats(24..31), 1],
                          [dec_pats(32..39), 1], [dec_pats(40..51), 1], [dec_pats(52..63), 1],
                          [dec_pats(64..75), 1],
                          [dec_pats(17, 19, 22, 23, 26, 27, 30, 31, 34, 35, 38, 39), 5]] },
  'S2-1-1' => { scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-1], 12]] },
  'S2-1-2' => { scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-1], 4], [%w[P2-1-2], 8]] },
  'S2-1-3' => { scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-3], 4], [%w[P2-1-4], 8]] },
  'S2-1-4' => { scale: :large, constraints: CONSTR_A_TENS_ZERO_ONE,
                entries: [[%w[P2-1-4], 1], [%w[P2-1-5], 3], [%w[P2-1-6], 8]] },
  'S2-1-5' => { scale: :large, constraints: CONSTR_TENS_ZERO_ONE,
                entries: [[%w[P2-1-7], 1], [%w[P2-1-8], 5], [%w[P2-1-9], 6]] },
  'S2-2-1' => { scale: :large, constraints: CONSTR_SUB_UNITS,
                entries: [[%w[P2-2-1], 12]] },
  'S2-2-2' => { scale: :large, constraints: CONSTR_SUB_UNITS,
                entries: [[%w[P2-2-1], 4], [%w[P2-2-2], 8]] },
  'S2-2-3' => { scale: :large, constraints: CONSTR_SUB_LOW2,
                entries: [[%w[P2-2-2], 1], [%w[P2-2-3], 2], [%w[P2-2-4], 2],
                          [%w[P2-2-7], 3], [%w[P2-2-8], 4]] },
  'S2-2-4' => { scale: :large, constraints: CONSTR_SUB_LOW2,
                entries: [[%w[P2-2-3], 1], [%w[P2-2-4], 1], [%w[P2-2-5], 1], [%w[P2-2-6], 1],
                          [%w[P2-2-7], 1], [%w[P2-2-8], 2], [%w[P2-2-9], 2], [%w[P2-2-10], 2],
                          [%w[P2-2-11], 1]] },
  'S3-1-1' => { scale: :small,
                entries: [[%w[P4-1-1], 4]] },
  'S3-1-2' => { scale: :small, constraints: CONSTR_CLOCK,
                entries: [[%w[P4-1-1], 1], [%w[P4-1-2], 3]] },
  'S3-1-3' => { scale: :small, constraints: CONSTR_CLOCK,
                entries: [[%w[P4-1-2], 1], [%w[P4-1-3], 3]] },
  'S3-1-4' => { scale: :small, constraints: CONSTR_CLOCK,
                entries: [[%w[P4-1-1 P4-1-2 P4-1-3], 1], [%w[P4-1-4], 3]] }
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
# 時計(:read)は a =「じ」・b =「ふん」で、解答は文字列(例: 3 じ 30 ふん)になる。
# minute は「ふん」を問うかどうか(解答欄に「ふん」を出すかの判断に使う)。
def gen_problem(pid)
  pat = PATTERNS[pid.upcase]
  a, b = pat[:gen].call
  op = pat[:op]
  ans = case op
        when :add then a + b
        when :sub then a - b
        when :mul then a * b
        when :read then clock_answer(a, b, pat[:minute])
        end
  prob = { a: a, b: b, op: op, ans: ans, pid: pat[:id] }
  op == :read ? prob.merge(minute: pat[:minute]) : prob
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

# コスト関数を評価する。引数が 2 つのものは「1 回(set)全体を見て 1 問のコストを
# 決める」形式(例: 回内での組の重複)なので、判定対象の回を渡す。
def cost_of(cost, prob, set)
  cost.arity == 2 ? cost.call(prob, set) : cost.call(prob)
end

# 1 回分の総コスト。
def total_cost(set, cost)
  set.sum { |p| cost_of(cost, p, set) }
end

# 同一パターン(pid)で全コスト関数が 0 になる問題を、可能な限り重複せず生成する。
# 重複回避は gen_unique と同じ段階で緩める(コスト 0 の条件は最後まで維持)。
#   set : 差し替え先の判定に使う回(1 回全体を見るコスト関数のため。差し替え対象は除く)
def gen_zero_cost(pid, hist, costs, set = [])
  zero = ->(prob) { costs.all? { |c| cost_of(c, prob, set).zero? } }
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
# 「1 回全体を見るコスト関数」(引数 2 つ。回内での組の重複など)も同じ枠組みで扱う。
#   all_costs : ステージの全コスト関数(差し替え先が全制約を満たすようにする)
def adjust!(set, hist, cost, max, all_costs)
  loop do
    total = total_cost(set, cost)
    break if total <= max

    target = set.select { |p| cost_of(cost, p, set).positive? }.max_by { |p| p[:n] }
    break unless target

    unrecord(hist, target)
    idx = set.index { |p| p[:n] == target[:n] }
    # 差し替え先の判定は対象を除いた回に対して行う(自分自身との重複を見ないため)。
    repl = gen_zero_cost(target[:pid], hist, all_costs, set - [target]).merge(n: target[:n])
    set[idx] = repl
    # 差し替えても総コストが減らないなら候補が枯渇している。無限ループを避けて打ち切る。
    break if total_cost(set, cost) >= total
  end
  set
end

# 前半(左側)に並べる問題数。半分(奇数なら切り上げ)。
# 1 列レイアウトのスケールでは振り分けを行わないため、全問を「前半」とする。
def left_count(num, scale = DEFAULT_SCALE)
  oneline?(scale) ? num : (num + 1) / 2
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

# 生成時の情報表示用。時計は --scale を使わないためスケールを出さない。
def form_desc(form, scale)
  form == :clock ? 'form=clock' : "form=#{form}, scale=#{scale}"
end

# 丸数字(①..⑳ / ㉑..㉟)を返す。
def circled(n)
  cp = n <= 20 ? 0x2460 + (n - 1) : 0x3251 + (n - 21)
  [cp].pack('U')
end

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
def typ_clock_face_defs
  <<~TYP

    // --- 時計盤(モノクロ / 長針・短針)---
    #let clock(hour, minute, size: 6cm, ink: black) = {
      let r = size / 2   // 半径
      let cx = r         // 中心 x
      let cy = r         // 中心 y

      // 12 時方向を基準に、時計回り ang・中心からの距離 rad の点を返す
      let pt(ang, rad) = (cx + rad * calc.sin(ang), cy - rad * calc.cos(ang))

      box(width: size, height: size, {
        // 外周の円
        let sw = 0.03 * r
        place(dx: sw / 2, dy: sw / 2, circle(radius: r - sw / 2, stroke: sw + ink))

        // 目盛り(分 = 細・時 = 太)
        for i in range(60) {
          let ang = i * 6deg
          let is-hour = calc.rem(i, 5) == 0
          let len = if is-hour { 0.12 * r } else { 0.06 * r }
          let tw  = if is-hour { 0.03 * r } else { 0.015 * r }
          place(line(start: pt(ang, r - 0.05 * r), end: pt(ang, r - 0.05 * r - len),
                     stroke: tw + ink))
        }

        // 数字 1-12
        let nr = 0.67 * r     // 数字を置く円の半径
        let cell = 0.32 * r   // 数字用セルの一辺
        for n in range(1, 13) {
          let p = pt(n * 30deg, nr)
          place(dx: p.at(0) - cell / 2, dy: p.at(1) - cell / 2,
            box(width: cell, height: cell,
              align(center + horizon,
                text(font: "#{body_font}", size: 0.20 * r, fill: ink)[#n])))
        }

        // 針(学習用に、中心から先端までで尾は出さない)
        let hand(ang, len, tw) = place(line(start: (cx, cy), end: pt(ang, len),
          stroke: (paint: ink, thickness: tw, cap: "round")))
        let hm = calc.rem(hour, 12)
        hand((hm + minute / 60) * 30deg, 0.52 * r, 0.055 * r)  // 短針: 太く短い
        hand(minute * 6deg, 0.80 * r, 0.035 * r)               // 長針: 細く長い

        // 中心の軸
        let dot = 0.05 * r
        place(dx: cx - dot, dy: cy - dot, circle(radius: dot, fill: ink))
      })
    }
  TYP
end

# 解答欄(角丸四角)の中の字。置き方が言語で異なるため定義を分ける。
# 幅は時計盤(直径 d)より左右 ansboxover ずつ広く、高さは h。
def typ_clockans_def
  lang == :en ? typ_clockans_en : typ_clockans_ja
end

# 日本語: 単位「じ」「ふん」を置く。
# 「ふん」は右端が角丸の始まり(右端 - 半径)より fundx 右、「じ」は右端が
# 解答欄の中央より jidx 左に来るように置く。どちらも下端は解答欄の下端から unitgap 上。
# showmin が偽のパターン(「ふん」を問わない)は「ふん」を出さず、
# 「じ」を「ふん」の位置(角丸の始まり。fundx のずらしはしない)に置く。
def typ_clockans_ja
  c = CLOCK_LAYOUT
  <<~TYP.chomp
    #let fundx = #{c[:fun_dx]}mm  // 「ふん」の右端を角丸の始まりから右へずらす量
    #let jidx  = #{c[:ji_dx]}mm  // 「じ」の右端を解答欄の中央から左へずらす量

    #let clockans(d, h, showmin) = {
      let w = d + 2 * ansboxover
      // 文字の右端の位置。右揃えの箱の幅で表す。
      let jiw = if showmin { w / 2 - jidx } else { w - ansboxr }
      box(width: w, height: h, stroke: ansboxthk, radius: ansboxr, {
        place(bottom + left, dy: -unitgap,
          box(width: jiw, align(right)[#text(size: unitfs)[#{t(:clock_hour_unit)}]]))
        if showmin {
          place(bottom + left, dy: -unitgap,
            box(width: w - ansboxr + fundx, align(right)[#text(size: unitfs)[#{t(:clock_min_unit)}]]))
        }
      })
    }
  TYP
end

# 英語: 単位は書かず、「It is」(左)と「．」(右)のあいだに下線を 1 本引く。
# 解答は「three fifteen」のように英単語で書くため、「ふん」の有無で置き方を変えない。
# 枠(角丸四角)は描かないが、占める幅と高さは日本語と同じにする。文字の左右の位置も
# 日本語と同じ基準(角丸の終わり / 始まり)から測るため、ansboxr は位置の基準として残す。
# 「It is」は左端が角丸の終わり(直線の始まり)より itisdx 左、「．」は右端が
# 角丸の始まりより perioddx 右。どちらも下端は解答欄の下端から unitgap 上。
# 下線は文字と同じ下端の高さに、「It is」の右端と「．」の左端から linegap ずつ空けて引く。
# 全体(「It is」・下線・「．」)は、日本語の「じ」「ふん」の位置より enlift 上に置く。
def typ_clockans_en
  c = CLOCK_LAYOUT
  <<~TYP.chomp
    #let itisdx   = #{c[:itis_dx]}mm  // 「It is」の左端を角丸の終わりから左へずらす量
    #let perioddx = #{c[:period_dx]}mm  // 「．」の右端を角丸の始まりから右へずらす量
    #let periodfs = #{c[:period_fs]}pt  // 「．」の文字サイズ(全角。見やすさのため大きめ)
    #let linegap  = #{c[:line_gap]}mm  // 下線の両端と「It is」「．」のあいだの空き
    #let enlift   = #{c[:en_lift]}mm  // 「It is」・下線・「．」の全体を上へずらす量
    #let enbase   = unitgap + enlift  // 解答欄の下端から、字と下線の下端までの距離

    #let clockans(d, h, showmin) = {
      let w = d + 2 * ansboxover
      let itis = text(size: unitfs)[#{t(:clock_itis)}]
      let period = text(size: periodfs)[#{t(:clock_period)}]
      box(width: w, height: h, {
        place(bottom + left, dx: ansboxr - itisdx, dy: -enbase, itis)
        // 「．」の右端の位置は、右揃えの箱の幅で表す。
        place(bottom + left, dy: -enbase,
          box(width: w - ansboxr + perioddx, align(right)[#period]))
        // 記入欄の下線。両端は文字の幅を測って決める。
        context {
          let x1 = ansboxr - itisdx + measure(itis).width + linegap
          let x2 = w - ansboxr + perioddx - measure(period).width - linegap
          place(bottom + left, dx: x1, dy: -enbase, line(length: x2 - x1, stroke: ansboxthk))
        }
      })
    }
  TYP
end

# 問題(時計・よみ)の定義。1 リージョンに 時計盤(上)と解答欄(下)を置く。
# 時計盤の直径はリージョンに収まる最大値(上限 clockdiam)を Typst 側で決める
# (リージョンの大きさは --num と見出しの高さで変わるため)。
def typ_clock_defs
  c = CLOCK_LAYOUT
  <<~TYP

    // --- 寸法(時計・よみ) ---
    #let clockdiam = #{c[:diam]}mm    // 時計盤の直径(リージョンに入らなければ縮める)
    #let ansboxh   = #{c[:boxh]}mm    // 解答欄の高さ
    #let ansboxover = #{c[:boxover]}mm  // 解答欄が時計盤からはみ出す幅(左右それぞれ)
    #let ansboxr   = #{c[:boxr]}mm     // 解答欄の角丸の半径
    #let ansboxthk = #{c[:boxthk]}pt   // 解答欄の線の太さ
    #let clockgap  = #{c[:gap]}mm     // 時計盤と解答欄のあいだの空き
    #let unitfs    = #{c[:unitfs]}pt   // 解答欄の中の字(「じ」「ふん」/「It is」)の文字サイズ
    #let unitgap   = #{c[:unitgap]}mm     // 解答欄の下端から中の字の下端までの距離
    #let rpadx     = #{c[:rpad_x]}mm     // リージョン内の左右の余白
    #let rpady     = #{c[:rpad_y]}mm     // 同・上下の余白
    #let numfs     = 12pt   // 問題番号(丸数字)のフォントサイズ

    #{typ_clockans_def}

    // 1 リージョン(1 問分)。時計盤は上、解答欄は下、どちらも左右中央に置く。
    // 番号は左上(place なので配置に影響しない。時計盤は丸いので重ならない)。
    // 大きさは layout でリージョンの実寸を測って決める。時計盤は clockdiam を
    // 上限にリージョンいっぱいまで大きくし、解答欄の高さは ansboxh を上限に
    // 時計盤の直径以下に抑える(リージョンが小さいときに解答欄だけが残らないように)。
    #let region(it) = block(width: 100%, height: 100%, inset: (x: rpadx, y: rpady), {
      place(top + left, text(size: numfs)[#it.n])
      layout(sz => {
        let avail = sz.height - clockgap   // 時計盤と解答欄で分け合う高さ
        // 解答欄が ansboxh に届かない(= 直径と同じ高さになる)なら avail の半分。
        let dmax = if avail / 2 <= ansboxh { avail / 2 } else { avail - ansboxh }
        // 幅は解答欄(直径 + 左右のはみ出し)がリージョンに収まる範囲まで。
        let d = calc.min(clockdiam, sz.width - 2 * ansboxover, dmax)
        grid(columns: (100%), rows: (auto, 1fr, auto), align: center,
          stroke: none, inset: 0pt,
          clock(it.h, it.m, size: d), [], clockans(d, calc.min(ansboxh, d), it.showmin))
      })
    })
  TYP
end

# リージョン割り(筆算・時計で共通)。見出し以降の残り領域を num 個のリージョンに
# 等分割し、1 リージョンに 1 問を置く。1 問の中身は呼び出し側が region で定義する。
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

# ---- メイン ------------------------------------------------------------

# ARGV から --lang の指定だけを先に読む。使い方(--help)やエラーの文言も
# --lang に従うため、OptionParser を組み立てる前に言語を確定させる必要がある。
# ここで拾えるのは完全な形の指定(--lang ja / --lang=ja)のみ。省略形は
# OptionParser が解釈するので、parse! の後にもう一度反映する。
def preparse_lang(argv)
  i = argv.index { |a| a == '--lang' || a.start_with?('--lang=') }
  return DEFAULT_LANG unless i

  to_lang(argv[i].start_with?('--lang=') ? argv[i].split('=', 2)[1] : argv[i + 1])
end

# 言語名(文字列)をシンボルにする。不正な値はエラーで終了する。
def to_lang(str)
  sym = str.to_s.downcase.to_sym
  abort t(:err_lang, list: LANGS.join('/'), v: str) unless LANGS.include?(sym)

  sym
end

main = lambda do
options = { pages: nil, num: nil, seed: nil,
            stage: nil, patterns: [], ratios: [], output: nil, stage_list: false,
            scale: nil, lang: nil }

lang!(preparse_lang(ARGV))

OptionParser.accept(Rational) do |s,|
  Rational(s)
rescue ArgumentError, ZeroDivisionError, TypeError
  raise OptionParser::InvalidArgument, s
end

parser = OptionParser.new do |o|
  o.banner = t(:usage)
  o.on('-s S', '--stage S', String, t(:opt_stage)) { |v| options[:stage] = v }
  o.on('-p P', '--pages P', Integer, t(:opt_pages)) { |v| options[:pages] = v }
  o.on('--stage-list', t(:opt_stage_list)) { options[:stage_list] = true }
  o.on('-n N', '--num N', Integer, t(:opt_num)) { |v| options[:num] = v }
  o.on('--pattern P', String, t(:opt_pattern)) { |v| options[:patterns] << v }
  o.on('--ratio R', Rational, t(:opt_ratio)) { |v| options[:ratios] << v }
  o.on('--scale S', String, t(:opt_scale)) { |v| options[:scale] = v }
  o.on('-o O', '--output O', String, t(:opt_output)) { |v| options[:output] = v }
  o.on('--lang L', String, t(:opt_lang)) { |v| options[:lang] = v }
  o.on('--seed S', Integer, t(:opt_seed)) { |v| options[:seed] = v }
  o.on('-h', '--help', t(:opt_help)) { puts o; exit }
end
parser.parse!(ARGV)

# 省略形(--lan など)で指定された場合はここで反映する(preparse_lang は完全形のみ)。
lang!(to_lang(options[:lang])) if options[:lang]

# --stage-list: 一覧表示して終了
if options[:stage_list]
  STAGES.each_key { |id| puts "#{id}\t#{stage_subtitle(id)}" }
  exit
end

# seed は未指定でも必ず確定させる(印刷後の対応づけと再現のため)。
# 完全な seed はログにのみ出力し、紙面には下位 16bit を 16 進 4 文字で入れる。
seed = options[:seed] || Random.new_seed
srand(seed)
tag = format('%04X', seed & 0xFFFF)
puts t(:seed_info, seed: seed, auto: options[:seed] ? '' : t(:seed_auto), tag: tag)

pages = options[:pages] || DEFAULT_PAGES
abort t(:err_pages, v: pages) if pages < 1
sets_count = 2 * pages

# --scale の検証(指定された場合のみ)。実際に採用するスケールはモード決定時に確定。
scale_opt = nil
if options[:scale]
  scale_opt = options[:scale].downcase.to_sym
  abort t(:err_scale, list: SCALES.keys.join('/'), v: options[:scale]) unless SCALES.key?(scale_opt)
end

# 出題モードの決定: --stage 優先、無ければ --pattern、いずれも無ければエラー。
stage_name = nil  # ステージ指定時のみサブタイトルを「第N回」の左に表示する
scale = DEFAULT_SCALE
form = :mental    # 出題形式(:mental=暗算 / :column=筆算)

if options[:stage]
  key = options[:stage].upcase
  stage = STAGES[key]
  abort t(:err_stage, v: options[:stage]) unless stage
  warn t(:warn_stage_opts) if !options[:patterns].empty? || !options[:ratios].empty? || options[:num]
  warn t(:warn_stage_scale) if scale_opt
  stage_name = stage_subtitle(key)
  scale = stage[:scale] # ステージ指定時は --scale を無視しステージ固有スケールを使う
  form = stage_form(stage)

  if stage[:special] == :kuku
    # 九九: 問題数・並び順・回数(4)が固定。--pages も無視。
    sets = make_kuku_sets
    num = 16
    puts t(:info_kuku, key: key, sub: stage_name, scale: scale)
  else
    num = stage_num(stage)
    # 筆算・時計は問題数 = リージョン数。分割できない問題数のステージは定義ミス。
    if form != :mental && !REGION_SHAPES.key?(num)
      abort t(:err_stage_region, key: key, num: num, shapes: REGION_SHAPES.keys.join(' / '))
    end
    # 履歴は全回で共有する(回をまたいだ重複回避のため)。
    hist = new_history(variety: form == :column)
    sets = Array.new(sets_count) { make_stage_set(stage, hist) }
    puts t(:info_stage, key: key, sub: stage_name, pages: pages, sets: sets_count,
                        num: num, desc: form_desc(form, scale))
  end

elsif !options[:patterns].empty?
  patterns = options[:patterns]
  unknown = patterns.reject { |p| PATTERNS.key?(p.upcase) }
  abort t(:err_pattern_unknown, list: unknown.join(', ')) unless unknown.empty?

  forms = patterns.map { |p| pattern_form(p) }.uniq
  abort t(:err_pattern_forms) if forms.size > 1
  form = forms.first

  if form == :mental
    num = options[:num] || DEFAULT_PROBLEMS
    unless (MIN_PROBLEMS..MAX_PROBLEMS).include?(num)
      abort t(:err_num_mental, min: MIN_PROBLEMS, max: MAX_PROBLEMS, v: num)
    end
  else
    # 筆算・時計: 問題数がリージョン分割形を決めるため、分割できる値のみ受け付ける。
    num = options[:num] || (form == :clock ? DEFAULT_CLOCK_REGIONS : DEFAULT_REGIONS)
    unless REGION_SHAPES.key?(num)
      abort t(:err_num_region, shapes: REGION_SHAPES.keys.join(' / '), v: num)
    end
  end

  ratios = options[:ratios]
  if ratios.empty?
    ratios = Array.new(patterns.size, Rational(1, patterns.size))
  else
    abort t(:err_ratio_count) unless ratios.size == patterns.size
    abort t(:err_ratio_negative) if ratios.any?(&:negative?)
    total = ratios.sum(0r)
    abort t(:err_ratio_zero) if total.zero?
    ratios = ratios.map { |r| r / total }
  end

  scale = scale_opt || DEFAULT_SCALE
  abort t(:err_scale_oneline, scale: scale) if form != :mental && oneline?(scale)
  warn t(:warn_clock_scale) if form == :clock && scale_opt

  hist = new_history(variety: form == :column)
  sets = Array.new(sets_count) { make_pattern_set(patterns, ratios, num, hist) }
  puts t(:info_pattern, list: patterns.join(', '), sets: sets_count, num: num,
                        desc: form_desc(form, scale))

else
  warn t(:err_no_mode)
  warn parser.help
  exit 1
end

# 出力先の決定
pdf_path = if options[:output]&.downcase&.end_with?('.pdf')
             options[:output]
           else
             warn t(:warn_output_ext, name: "#{BASENAME}.pdf") if options[:output]
             "#{BASENAME}.pdf"
           end
typ_path = pdf_path.sub(/\.pdf\z/i, '.typ')

# 大見出しは出題形式で決まる。
title_text = { column: t(:title_column), clock: t(:title_clock) }.fetch(form, t(:title_mental))

File.write(typ_path, build_typst(sets, num, title_text, stage_name, scale, form, tag))
puts t(:info_typ, path: typ_path)

if system('typst', 'compile', typ_path, pdf_path)
  pages_out = begin
    `pdfinfo #{pdf_path} 2>/dev/null`[/Pages:\s*(\d+)/, 1]
  rescue StandardError
    nil
  end
  puts t(:info_pdf, path: pdf_path, pages: pages_out ? t(:pages_suffix, n: pages_out) : '')
else
  warn t(:err_typst)
  exit 1
end
end

main.call if __FILE__ == $PROGRAM_NAME
