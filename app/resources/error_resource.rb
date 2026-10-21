class ErrorResource
  include Alba::Resource

  root_key :error

  attributes :code, :message, :details
end
