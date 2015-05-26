require "spec_helper"
require "teamsnap"

RSpec.describe "teamsnap_rb", :vcr => true do
  before(:all) do
    VCR.use_cassette("apiv3-init") do
      TeamSnap.init(
        :url => "http://localhost:3000",
        :token => "1-classic-dont_tell_the_cops",
        :backup_cache => false
      )
    end
  end

  it "registers new classes via introspection of the root collection" do
    expect { TeamSnap::Team }.to_not raise_error
  end

  it "handles fetching data via queries" do
    ts = TeamSnap::Team.search(:id => 1)

    expect(ts).to_not be_empty
    expect(ts[0].id).to eq(1)
  end

  it "handles queries with no data" do
    ts = TeamSnap::Team.search(:id => 0)

    expect(ts).to be_empty
  end

  it "raises an exception when a query is invalid" do
    expect {
      TeamSnap::Team.search(:foo => :bar)
    }.to raise_error(
      ArgumentError,
      "Invalid argument(s). Valid argument(s) are [:id, :team_id, :user_id, :division_id]"
    )
  end

  it "handles executing an action via commands" do
    ms = TeamSnap::Member.disable_member(:member_id => 1)

    expect(ms).to_not be_empty
    expect(ms[0].id).to eq(1)
  end

  it "raises and exception when a command is invalid" do
    expect {
      TeamSnap::Member.disable_member(:foo => :bar)
    }.to raise_error(
      ArgumentError,
      "Invalid argument(s). Valid argument(s) are [:member_id]"
    )
  end

  it "can handle errors generated by command" do
    expect {
      TeamSnap::Member.disable_member
    }.to raise_error(
      TeamSnap::Error,
      "You must provide the member_id."
    )
  end

  it "adds .find if .search is available" do
    t = TeamSnap::Team.find(1)

    expect(t.id).to eq(1)
  end

  it "raises an exception if .find returns nothing" do
    expect {
      TeamSnap::Team.find(0)
    }.to raise_error(
      TeamSnap::NotFound,
      "Could not find a TeamSnap::Team with an id of '0'."
    )
  end

  it "can follow singular links" do
    m = TeamSnap::Member.find(1)
    t = m.team

    expect(t.id).to eq(1)
  end

  it "can handle links with no data" do
    m = TeamSnap::Member.find(1)
    as = m.assignments

    expect(as).to be_empty
  end

  it "can follow plural links" do
    t = TeamSnap::Team.find(1)
    ms = t.members

    expect(ms.size).to eq(10)
  end

  it "can use bulk load" do
    cs = TeamSnap.bulk_load(:team_id => 1, :types => "team,member")

    expect(cs).to_not be_empty
    expect(cs.size).to eq(11)
    expect(cs[0]).to be_a(TeamSnap::Team)
    expect(cs[0].id).to eq(1)
    cs[1..10].each_with_index do |c, idx|
      expect(c).to be_a(TeamSnap::Member)
      expect(c.id).to eq(idx+1)
    end
  end

  it "can handle an empty bulk load" do
    cs = TeamSnap.bulk_load(:team_id => 0, :types => "team,member")

    expect(cs).to be_empty
  end

  it "can handle an error with bulk load" do
    expect {
      TeamSnap.bulk_load
    }.to raise_error(
      TeamSnap::Error,
      "You must include a team_id parameter"
    )
  end

  it "adds href to items" do
    m = TeamSnap::Member.find(1)

    expect(m.href).to eq("http://localhost:3000/members/1")
  end

  context "supports relations with expected behaviors" do
    let(:event) { TeamSnap::Event.find(1) }

    context "when a plural relation is called" do
      it "responds with an array of objects when successful" do
        a = event.availabilities
        expect(a.size).to be > 0
        expect(a).to be_an(Array)
      end

      it "responds with an empty array when no objects exist" do
        a = event.assignments
        expect(a.size).to eq(0)
        expect(a).to be_an(Array)
      end
    end

    context "when a singular relation is called" do
      it "responds with the object if it exists" do
        a = event.team
        expect(a).to be_a(TeamSnap::Team)
      end

      it "responds with nil if it does NOT exist" do
        a = event.division_location
        expect(a).to be_a(NilClass)
      end
    end
  end

  context "supports using a backup file on init for when API cannot be reached" do
    context ".backup_file" do
      let(:default_file_location) { "./tmp/.teamsnap_rb" }

      it "responds with the given file location if provided" do
        file_location = "./some_dir/some_file.testing"
        expect(TeamSnap.backup_file(file_location)).to eq(file_location)
      end

      it "responds with the default file location if not set" do
        expect(TeamSnap.backup_file(nil)).to eq(default_file_location)
      end

      it "responds with the default file location if set to true" do
        expect(TeamSnap.backup_file(true)).to eq(default_file_location)
      end
    end

    context ".write_backup_file" do
      let(:collection) { {:one => 1} }

      context "when the given directory exists" do
        let(:test_file_location) { "./tmp/.teamsnap_rb" }
        let(:file_contents) { Oj.dump(collection) }

        it "returns the number of characters written to the file" do
          expect(TeamSnap.write_backup_file(test_file_location, collection)).to eq(file_contents.length)
        end

        it "writes the file inside the directory provided" do
          expect(File).to receive(:open).with(test_file_location, "w+")
          TeamSnap.write_backup_file(test_file_location, collection)
        end

        it "writes the file with the correct information" do
          TeamSnap.write_backup_file(test_file_location, collection)
          file_contents = Oj.load(IO.read(test_file_location))
          expect(file_contents).to eq(collection)
        end
      end

      context "when the given directory does NOT exist" do
        let(:test_file_location) { "./directory_doesnt_exist/file" }
        let(:test_dir_location) { File.dirname(test_file_location) }
        let(:warning_message) {
          "WARNING: Directory '#{test_dir_location}' does not exist. " +
          "Backup cache functionality will not work until this is resolved."
        }

        it "issues a warning that the directory does not exist" do
          expect(TeamSnap).to receive(:warn).with(warning_message)
          TeamSnap.write_backup_file(test_file_location, collection)
        end
      end
    end

    context ".backup_file_exists?" do
      it "returns false if backup_cache_file is NOT set" do
        opts = {}
        expect(TeamSnap.backup_file_exists?(opts)).to eq(false)
      end

      it "returns false if the file does NOT exist" do
        opts = { :backup_cache_file => "./some_file_that_does_not_exist"}
        expect(TeamSnap.backup_file_exists?(opts)).to eq(false)
      end

      it "returns true is the file exists" do
        opts = { :backup_cache_file => "./Gemfile"}
        expect(TeamSnap.backup_file_exists?(opts)).to eq(true)
      end
    end
  end
end
