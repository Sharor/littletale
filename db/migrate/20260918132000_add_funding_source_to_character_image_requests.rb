class AddFundingSourceToCharacterImageRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :character_image_requests, :funding_source, :string
    add_index :character_image_requests, :funding_source
  end
end
