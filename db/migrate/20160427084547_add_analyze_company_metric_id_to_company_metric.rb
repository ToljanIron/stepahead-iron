class AddAnalyzeCompanyMetricIdToCompanyMetric < ActiveRecord::Migration[4.2]
  def change
    add_column :company_metrics, :analyze_company_metric_id, :integer
    add_index :company_metrics, :analyze_company_metric_id
  end
end
