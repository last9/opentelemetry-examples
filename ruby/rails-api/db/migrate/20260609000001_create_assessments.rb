class CreateAssessments < ActiveRecord::Migration[7.1]
  def change
    create_table :assessments do |t|
      t.string :type                       # STI discriminator
      t.string :kind, null: false          # default_scope partition key (set per subclass)
      t.string :title
      t.datetime :resolved_at              # drives the :unresolved scope
      t.string :state, default: 'open'     # drives the :critical scope
      t.timestamps
    end
    add_index :assessments, :type
  end
end
