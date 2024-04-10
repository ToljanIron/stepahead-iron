class AddIndexes < ActiveRecord::Migration[4.2]
  def change
    add_index :domains, :company_id, name: 'index_domains_on_company_id'
    add_index :employee_alias_emails, :employee_id, name: 'index_alias_emails_on_employee_id'
    add_index :employee_management_relations, :employee_id, name: 'index_employee_management_relations_on_employee_id'
    add_index :employees, :company_id, name: 'index_employees_on_company_id'
    add_index :employees_pins, :employee_id, name: 'index_employees_pins_on_employee_id'
    add_index :groups, :company_id, name: 'index_groups_on_company_id'
    add_index :job_titles, :company_id, name: 'index_job_titles_on_company_id'
    add_index :job_to_api_client_task_convertors, :job_id, name: 'index_job_to_api_client_task_convertors_on_job_id'
    add_index :jobs_archives, :job_id, name: 'index_jobs_archives_on_job_id'
    add_index :jobs_queues, :job_id, name: 'index_jobs_queues_on_job_id'
    add_index :offices, :company_id, name: 'index_offices_on_company_id'
    add_index :pins, :company_id, name: 'index_pins_on_company_id'
    add_index :qualifications, :company_id, name: 'index_qualifications_on_company_id'
    add_index :raw_data_entries, :company_id, name: 'index_raw_data_entries_on_company_id'
    add_index :raw_data_entries, :msg_id, name: 'index_raw_data_entries_on_msg_id'
    add_index :scheduled_api_client_tasks, :api_client_task_definition_id, name: 'index_scheduled_api_client_tasks_on_task_definition_id'
    add_index :scheduled_api_client_tasks, :jobs_queue_id, name: 'index_scheduled_api_client_tasks_on_jobs_queue_id'
    add_index :scheduled_api_client_tasks, :api_client_id, name: 'index_scheduled_api_client_tasks_on_api_client_id'
    add_index :stack_of_images, :img_name, name: 'stack_of_images_on_img_name'
  end
end
