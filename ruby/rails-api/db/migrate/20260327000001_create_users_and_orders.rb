class CreateUsersAndOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name
      t.string :role, default: 'member'
      t.string :plan, default: 'free'
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :role

    create_table :orders do |t|
      t.references :user, foreign_key: true
      t.string :order_number, null: false
      t.decimal :total, precision: 10, scale: 2
      t.string :status, default: 'pending'
      t.string :shipping_method
      t.text :notes
      t.timestamps
    end
    add_index :orders, :order_number, unique: true
    add_index :orders, :status

    create_table :order_items do |t|
      t.references :order, foreign_key: true
      t.string :product_name, null: false
      t.integer :quantity, default: 1
      t.decimal :unit_price, precision: 10, scale: 2
      t.timestamps
    end
  end
end
