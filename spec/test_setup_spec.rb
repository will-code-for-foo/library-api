require 'rails_helper'

RSpec.describe 'Test setup' do
  it 'runs against PostgreSQL' do
    expect(ActiveRecord::Base.connection.adapter_name).to eq('PostgreSQL')
  end

  it 'exposes the FactoryBot methods without a prefix' do
    expect(self).to respond_to(:build, :create, :build_stubbed, :attributes_for)
  end

  describe 'shoulda-matchers one-liners', type: :model do
    subject(:widget) { Widget.new }

    before do
      stub_const('Widget', Class.new do
        include ActiveModel::Model

        attr_accessor :name

        validates :name, presence: true
      end)
    end

    it { is_expected.to validate_presence_of(:name) }
  end
end
