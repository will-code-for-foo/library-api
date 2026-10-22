require 'rails_helper'

RSpec.describe 'config/recurring.yml' do
  let(:schedule) { ActiveSupport::ConfigurationFile.parse(Rails.root.join('config/recurring.yml')) }

  %w[development production].each do |environment|
    describe "in #{environment}" do
      let(:task_options) { schedule.fetch(environment).fetch('send_loan_reminders') }
      let(:task) { SolidQueue::RecurringTask.from_configuration('send_loan_reminders', **task_options.symbolize_keys) }

      it 'schedules the reminders job as a valid Solid Queue recurring task' do
        expect(task_options['class']).to eq('SendLoanRemindersJob')
        expect(task).to be_valid
      end

      it 'runs it once a day' do
        cron = Fugit.parse(task_options['schedule'])
        first_run = cron.next_time
        second_run = cron.next_time(first_run)
        third_run = cron.next_time(second_run)

        expect([ second_run - first_run, third_run - second_run ]).to all(eq(1.day.to_i))
      end
    end
  end
end
