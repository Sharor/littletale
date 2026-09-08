class RenameAssessmentGenerationModel < ActiveRecord::Migration[8.0]
  def change
    rename_column :character_image_assessments, :model_name, :generation_model
  end
end
