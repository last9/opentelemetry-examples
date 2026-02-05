class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions do |t|
      t.string :transaction_id, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency, default: 'USD'
      t.string :status, default: 'pending'
      t.string :payment_method
      t.string :user_id
      t.text :metadata

      t.timestamps
    end

    add_index :transactions, :transaction_id, unique: true
    add_index :transactions, :user_id
    add_index :transactions, :status
  end
end
