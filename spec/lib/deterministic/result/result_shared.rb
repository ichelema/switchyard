shared_examples 'Result' do
  let(:result_name) { described_class.name.split("::")[-1] }
  specify { expect(subject.value).to eq 1 }
  specify { expect(result.new(subject)).to eq result.new(1) }

  it "#fmap" do
    expect(result.new(1).fmap { |e| e + 1 }).to eq result.new(2)
  end

  it "#bind" do
    expect(result.new(1).bind { |v| result.new(v + 1) }).to eq result.new(2)
  end

  it "#to_s" do
    expect(result.new(1).to_s).to eq "1"
    # il formato di Hash#to_s/inspect cambia tra Ruby 3.3 e 3.4: costruiamo l'atteso dinamicamente
    expect(result.new(:a => 1).to_s).to eq({ :a => 1 }.to_s)
  end

  it "#inspect" do
    expect(result.new(1).inspect).to eq "#{result_name}(1)"
    expect(result.new(:a => 1).inspect).to eq "#{result_name}(#{{ :a => 1 }.inspect})"
  end
end

