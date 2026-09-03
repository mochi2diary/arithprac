# frozen_string_literal: true

# 制約(コスト関数 COST_* / CONSTR_*)。stages.rb より先に読む。

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

