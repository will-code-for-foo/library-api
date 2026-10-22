class AddReminderTimestampsToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :three_days_reminder_sent_at, :datetime
    add_column :loans, :due_date_reminder_sent_at, :datetime
  end
end
