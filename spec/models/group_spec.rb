require 'spec_helper'

describe Group, type: :model do
  def create_groups
    Company.create!(id: 0, name: 'comp')
    @parent_group = FactoryBot.create(:group, name: 'parent', company_id: 0, snapshot_id: 1)
    @child_group =  FactoryBot.create(:group, name: 'child', company_id: 0, parent_group_id: @parent_group.id, snapshot_id: 1)
    @child_group_employees_ids = []
    @parent_group_employees_ids = []
    @total_employess = rand(100) + 2
  end

  def create_employees
    (1..@total_employess).each do
      e = FactoryBot.create(:employee, snapshot_id: 1)
      if rand(100) > 50
        e.group = @parent_group
        @parent_group_employees_ids.push e.id
      else
        e.group = @child_group
        @child_group_employees_ids.push e.id
      end
      e.save!
    end
  end

  subject { @group }

  before do
    @group = Group.new
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
    FactoryBot.reload
  end

  it { is_expected.to respond_to(:name) }
  it { is_expected.to respond_to(:company_id) }
  it { is_expected.to respond_to(:parent_group_id) }

  describe 'prepare_groups_for_hierarchy_queries' do
    sid = nil
    before do
      DatabaseCleaner.clean_with(:truncation)
      FactoryBot.reload

      Company.create(id: 1, name: "Hevra10").id
      sid = Snapshot.create(name: "2016-01", company_id: 1, timestamp: 3.weeks.ago).id
      root1 = Group.create(name: "Root1", company_id: 1, external_id: '1' )
      root2 = Group.create(name: "Root2", company_id: 1, external_id: '2' )
      Group.create(name: "son1",  company_id: 1, external_id: '11', parent_group_id: root1.id )
      Group.create(name: "son2",  company_id: 1, external_id: '21', parent_group_id: root2.id )
      Group.create(name: "son3",  company_id: 1, external_id: '22', parent_group_id: root2.id )
    end

    it 'should be able to assign ns values when there are multiple roots' do
      Group.prepare_groups_for_hierarchy_queries(sid)

      g1 = Group.find_by_external_id('1')
      g11 = Group.find_by_external_id('11')
      g2 = Group.find_by_external_id('2')
      g21 = Group.find_by_external_id('21')
      g22 = Group.find_by_external_id('22')

      expect( g1.nsleft ).to be < g11.nsleft
      expect( g21.nsright ).to be < g22.nsleft
      expect( g22.nsright ).to be < g2.nsright

      # The values of g1 should be either both larger or both smaller than those of g2
      comperator = (g1.nsright - g2.nsright) * (g1.nsleft - g2.nsleft)
      expect( comperator ).to be > 1
    end

    it 'should not fail when there are lone groups' do
      Group.create(name: "root3",  company_id: 1, external_id: '3')
      Group.prepare_groups_for_hierarchy_queries(sid)

      nsnumbers = Group.pluck(:nsleft, :nsright).flatten.uniq
      expect( nsnumbers.length ).to eq(12)

    end
  end

  describe ', with invalid data should be invalid' do
    it { is_expected.not_to be_valid }
  end

  describe ', with valid data should be valid' do
    it do
      subject[:name] = 'some name'
      subject[:company_id] = 0
      is_expected.to be_valid
    end
  end

  describe ', model functionality' do

    before(:each) do
      create_groups
      create_employees
    end

    after do
      FactoryBot.reload
    end

    it ', parent group contain all employees' do
      res = @parent_group.extract_employees.count
      expect(res).to eq(@total_employess)
    end

    it ', parent_group should contain the set of all employees' do
      res = @parent_group.extract_employees | @child_group.extract_employees
      expected = @parent_group_employees_ids | @child_group_employees_ids
      expect(res.sort).to eq(expected.sort)
    end

    it ', child_group should be a subset of parent_group' do
      res = @child_group.extract_employees
      expect(res.sort).to eq(@child_group_employees_ids.sort)
    end

    describe ', pack_to_json' do

      it ', parent_group should return hashed summary' do
        res = @parent_group.pack_to_json
        expect(res[:id]).to eq(@parent_group.id)
        expect(res[:name]).to eq(@parent_group.name)
        expected = @parent_group_employees_ids | @child_group_employees_ids
        expect(res[:employees_ids].sort).to eq(expected.sort)
        expect(res[:child_groups]).to eq([@child_group.id])
        expect(res[:parent]).to be_nil
      end

      it ', child_group should return hashed summary' do
        res = @child_group.pack_to_json
        expect(res[:id]).to eq(@child_group.id)
        expect(res[:name]).to eq(@child_group.name)
        expect(res[:employees_ids].sort).to eq(@child_group_employees_ids.sort)
        expect(res[:child_groups]).to eq([])
        expect(res[:parentId]).to eq(@parent_group.id)
      end
    end
  end

  describe 'sibling_groups' do
    it 'should return groups under same parent' do
      FactoryBot.create_list(:group, 4)
      Group.first(2).each { |g| g.update(parent_group_id: 100) }
      Group.last(2).each { |g| g.update(parent_group_id: 1) }
      expect(Group.first.sibling_groups).to eq([Group.second])
    end
  end

  describe 'create_snapshot in groups' do
    before do
      Snapshot.create!(id: 100, company_id: 1, timestamp: 1.week.ago)
      Snapshot.create!(id: 101, company_id: 1, timestamp: Time.now)
      FactoryBot.create_list(:group, 2)
      Group.last.update(parent_group_id: 1)
      Group.update_all(snapshot_id: 100)
    end

    it 'should create a new snapshot 101 from snapshot 100' do
      Group.create_snapshot(1, 100, 101)
      expect(Group.count).to eq(4)
      expect(Group.last.snapshot_id).to eq(101)
    end

    it 'should do nothing if groups already exists in this snapshot' do
      Group.create_snapshot(1, 100, 101)
      expect(Group.count).to eq(4)
      Group.create_snapshot(1, 100, 101)
      expect(Group.count).to eq(4)
      expect(Group.last.snapshot_id).to eq(101)
    end

    it 'should create a new snapshot 101 from snapshot 100 with the change in parent_group_id' do
      Group.create_snapshot(1, 100, 101)
      expect(Group.count).to eq(4)
      expect(Group.last.snapshot_id).to eq(101)
      expect(Group.last.parent_group_id).to eq(3)
    end

    it 'should not copy over inactive groups to new snapshot' do
      Group.last.update(active: false)
      Group.create_snapshot(1, 100, 101)
      expect(Group.count).to eq(3)
    end
  end

  describe 'find_groups_in_snapshot' do

    before do
      Snapshot.create!(id: 4, company_id: 1, timestamp: 1.week.ago)
      FactoryBot.create_list(:group, 4, snapshot_id: 3)
      rootgid = Group.where(name: 'group_1').last.id
      Group.where
           .not(name: 'group_1')
           .update_all(parent_group_id: rootgid)
      Group.create_snapshot(1, 3, 4)
      @gids = Group.where(snapshot_id: 3).pluck(:id)
    end

    it 'should return array of same size and values of type Integer' do
      res = Group.find_group_ids_in_snapshot(@gids, 4)
      expect(res.length).to eq(4)
      expect(res[0].class).to eq(Integer)
    end

    it 'should return empty if groups argument is empty' do
      res = Group.find_group_ids_in_snapshot([], 4)
      expect(res.length).to eq(0)
    end

    it 'should return nil if target snapshot does not exist' do
      res = Group.find_group_ids_in_snapshot([], 5)
      expect(res.length).to eq(0)
    end

    it 'should return an empty list if gids do not exist in sid' do
      res = Group.find_group_ids_in_snapshot([200, 201], 4)
      expect(res.length).to eq(0)
    end

    it 'should return a partial list if some gids do not exist in sid' do
      res = Group.find_group_ids_in_snapshot(@gids + [200], 4)
      expect(res.length).to eq(4)
    end
  end

  describe 'get_all_subgroups' do
    before do
      Company.create!(id: 0, name: 'comp')
      FactoryBot.create(:group, id: 1, name: 'g1', company_id: 1, parent_group_id:  nil)
      FactoryBot.create(:group, id: 2, name: 'g2', company_id: 1, parent_group_id:  1)
      FactoryBot.create(:group, id: 3, name: 'g3', company_id: 1, parent_group_id:  1)
      FactoryBot.create(:group, id: 4, name: 'g4', company_id: 1, parent_group_id:  2)
      FactoryBot.create(:group, id: 5, name: 'g5', company_id: 1, parent_group_id:  3)
      FactoryBot.create(:group, id: 6, name: 'g6', company_id: 1, parent_group_id:  3)
      FactoryBot.create(:group, id: 7, name: 'g7', company_id: 1, parent_group_id:  6)
      FactoryBot.create(:group, id: 8, name: 'g8', company_id: 1, parent_group_id:  6)
    end

    it 'should get all subgroups' do
      gids = Group.get_all_subgroups(3).sort
      expect(gids).to eq([3,5,6,7,8])
    end

    it 'parent group result should return son group result' do
      parent_gids = Group.get_all_subgroups(3)
      son_gids    = Group.get_all_subgroups(6)
      son_gids.each do |sgid|
        expect(parent_gids.include?(sgid)).to be_truthy
      end
    end

    it 'should return own group only if group is leaf' do
      groups = Group.get_all_subgroups(4)
      expect(groups).to eq([4])
    end
  end

end

describe 'nested sets handling' do
  pairs = [[1,2],[2,4],[1,3],[3,5],[3,6],[6,7],[6,8]]

  before :all do
    FactoryBot.create(:group, id: 1, name: 'g1', parent_group_id:  nil)
    FactoryBot.create(:group, id: 2, name: 'g2', parent_group_id:  1)
    FactoryBot.create(:group, id: 3, name: 'g3', parent_group_id:  1)
    FactoryBot.create(:group, id: 4, name: 'g4', parent_group_id:  2)
    FactoryBot.create(:group, id: 5, name: 'g5', parent_group_id:  3)
    FactoryBot.create(:group, id: 6, name: 'g6', parent_group_id:  3)
    FactoryBot.create(:group, id: 7, name: 'g7', parent_group_id:  6)
    FactoryBot.create(:group, id: 8, name: 'g8', parent_group_id:  6)

    Group.create_nested_sets_structure(pairs, 1)
  end

  it 'should get all descendants node 3' do
    res = Group.get_descendants(3)
    expect(res).to eq( [5,6,7,8] )
  end

  it 'should return empty list for a leaf' do
    res = Group.get_descendants(7)
    expect(res).to eq( [] )
  end

  it 'should get all ancestors of node 7' do
    res = Group.get_ancestors(7)
    expect(res).to eq( [1,3,6] )
  end

  it 'should get all group pairs in DFS order' do
    res = Group.get_all_parent_son_pairs(1)
    expect(res).to eq(pairs)
  end
end
