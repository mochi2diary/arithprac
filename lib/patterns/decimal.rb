# frozen_string_literal: true

# 暗算-小数乗算パターン(P3-3)と小数計算の基盤(dec_* / def_dec_pattern)。

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

