shared_examples 'a Monad' do
  describe 'axioms' do
    it '1st monadic law: left-identity' do
      f = ->(value) { monad.new(value + 1) }
      expect(
        monad.new(1).bind do |value|
          f.call(value)
        end
      ).to eq f.call(1)
    end

    it '2nd monadic law: right-identy - new and bind do not change the value' do
      expect(
        monad.new(1).bind do |value|
          monad.new(value)
        end
      ).to eq monad.new(1)
    end

    it '3rd monadic law: associativity' do
      f = ->(value) { monad.new(value + 1)   }
      g = ->(value) { monad.new(value + 100) }

      id1 = monad.new(1).bind { |a| f.call(a) }.bind { |b| g.call(b) }

      id2 = monad.new(1).bind do |a|
        f.call(a).bind do |b|
          g.call(b)
        end
      end

      expect(id1).to eq id2
    end

    it '#bind must return a monad' do
      expect(monad.new(1).bind { |v| monad.new(v) }).to eq monad.new(1)
      # rubocop:disable Lint/EmptyBlock
      expect { monad.new(1).bind {} }.to raise_error(FunctionalLightService::Monad::NotMonadError)
      # rubocop:enable Lint/EmptyBlock
    end

    it '#new must return a monad' do
      expect(monad.new(1)).to be_a monad
    end
  end
end
