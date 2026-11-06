# DHH::Deadline: a time budget on the monotonic clock, shared by every step of one operation.

module DHH
  class Deadline
    def self.after(seconds)
      new(seconds)
    end

    private_class_method :new

    def initialize(seconds)
      @expires_at = now + seconds
    end

    # Seconds left; zero or negative once expired.
    def remaining
      @expires_at - now
    end

    def expired?
      remaining <= 0
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
