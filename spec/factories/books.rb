FactoryBot.define do
  factory :book do
    sequence(:serial_number) { |n| format("%06d", n) }
    sequence(:title) { |n| "Title #{n}" }
    author { "Author" }
  end
end
