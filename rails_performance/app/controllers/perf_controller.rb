class PerfController < ApplicationController
  def do_work
    5.times do 
      monkey = Monkey.create! :name => rand_string

      5.times do
        monkey.shields.create! :strength => rand(100)
      end

      monkey.destroy
    end

    @monkey = Monkey.create! :name => 'harry'
    @monkey.shields.create! :strength => 10
  end
  private
  
  L=([*?a..?z]+[*?A..?Z]+[*?0..?9]).map(&:chr)
  def rand_string
    Array.new(10){L[rand L.size]}*''
  end
end
