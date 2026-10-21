FactoryBot.define do
  factory :loan do
    book
    reader
    borrowed_at { Time.current }

    trait :returned do
      returned_at { borrowed_at + 1.day }
    end
  end
end
