FactoryBot.define do
  factory :reader do
    sequence(:card_number) { |n| format("%06d", n) }
    sequence(:name) { |n| "Reader #{n}" }
    sequence(:email) { |n| "reader#{n}@example.com" }
  end
end
