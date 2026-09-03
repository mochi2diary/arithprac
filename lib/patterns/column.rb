# frozen_string_literal: true

# 筆算パターン(加算 P2-1 / 減算 P2-2)と sub_borrows。

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

