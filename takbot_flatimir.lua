require 'tak_AI'
game = tak.new(5)
game:play_game_from_ptn(io.read('*a'))
takai = make_takarlo_01(75,true)
print(takai:move(game))
