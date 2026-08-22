class ApplicationJob < ActiveJob::Base
  # A job whose record has since been deleted has nothing left to do.
  discard_on ActiveJob::DeserializationError

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
end
