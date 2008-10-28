class MakeSomeStuff < ActiveRecord::Migration
  def self.up
    create_table :monkeys do |t|
      t.string :name
      t.timestamps
    end

    create_table :shields do |t|
      t.integer :strength
      t.belongs_to :monkey
      t.timestamps
    end
  end

  def self.down
    drop_table :monkeys
    drop_table :shields
  end
end
