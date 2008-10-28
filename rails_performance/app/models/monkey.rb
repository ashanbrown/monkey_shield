class Monkey < ActiveRecord::Base
  has_many :shields, :dependent => :destroy
end
