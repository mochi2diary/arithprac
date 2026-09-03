# frozen_string_literal: true

# 問題生成・出題履歴(重複回避)・セット構築。

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

