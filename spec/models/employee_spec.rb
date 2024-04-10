require 'spec_helper'

describe Employee, type: :model do
  before do
    @employee = FactoryBot.build(:employee)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
    FactoryBot.reload
  end

  subject { @employee }

  it { is_expected.to be_valid }

  it 'direct_managers_by_company should list all employees who are also direct managers' do
    c = Company.create(name: 'company lala')
    e1 = FactoryBot.create(:employee, company_id: c.id)
    e2 = FactoryBot.create(:employee, company_id: c.id)
    EmployeeManagementRelation.create(manager_id: e1.id, employee_id: e2.id, relation_type: 0)
    res = Employee.direct_managers_by_company(c.id)
    expect(res.count).to eq(1)
    res2 = Employee.pro_managers_by_company(c.id)
    expect(res2.count).to eq(0)
  end

  it 'professional_managers_by_company should list all employees who are also professional managers' do
    c = Company.create(name: 'company lala')
    e1 = FactoryBot.create(:employee, company_id: c.id)
    e2 = FactoryBot.create(:employee, company_id: c.id)
    EmployeeManagementRelation.create(manager_id: e1.id, employee_id: e2.id, relation_type: 1)
    res = Employee.pro_managers_by_company(c.id)
    expect(res.count).to eq(1)
  end

  it 'job titles should dispplay all job titles' do
    c = Company.create(name: 'company lala')
    j1 = JobTitle.create(name: 'Janitor', company_id: c.id, color_id: 1)
    j2 = JobTitle.create(name: 'Bum', company_id: c.id, color_id: 2)
    FactoryBot.create(:employee, company_id: c.id, job_title_id: j1.id)
    FactoryBot.create(:employee, company_id: c.id, job_title_id: j2.id)
    res = Employee.job_title_by_company(c.id)
    expect(res.count).to eq(2)
    res.should include('Janitor')
    res.should include('Bum')
  end

  describe 'when first name is not present' do
    before { @employee.first_name = ' ' }
    it { is_expected.not_to be_valid }
  end

  describe 'when last name is not present' do
    before { @employee.last_name = ' ' }
    it { is_expected.not_to be_valid }
  end

  describe 'when email is not present' do
    before { @employee.email = ' ' }
    it { is_expected.not_to be_valid }
  end

  describe 'when firstt name is too long' do
    before { @employee.first_name = 'a' * 51 }
    it { is_expected.not_to be_valid }
  end

  describe 'when last name is too long' do
    before { @employee.last_name = 'a' * 51 }
    it { is_expected.not_to be_valid }
  end

  describe 'when email format is invalid' do
    it 'should be invalid' do
      addresses = %w(employee@foo,com user_at_foo.org example.employee@foo.
                     foo@bar_baz.com foo@bar+baz.com)
      addresses.each do |invalid_address|
        @employee.email = invalid_address
        expect(@employee).not_to be_valid
      end
    end
  end

  describe 'when email format is valid' do
    it 'should be valid' do
      addresses = %w(employee@foo.COM A_US-ER@f.b.org frst.lst@foo.jp a+b@baz.cn)
      addresses.each do |valid_address|
        @employee.email = valid_address
        expect(@employee).to be_valid
      end
    end
  end

  describe ', pack_to_json' do
    g = nil
    o = nil
    e = nil
    before do
      g = FactoryBot.create(:group)
      o = FactoryBot.create(:office)
      age_group = FactoryBot.create(:age_group, name: '25-34')
      seniority = FactoryBot.create(:seniority, name: '2Y')
      e = FactoryBot.create(
        :employee,
        email: 'a@mail.com',
        first_name: 'A',
        last_name: 'A',
        company_id: 1,
        gender: :female,
        group: g,
        date_of_birth: 30.years.ago,
        rank_id: 0,
        age_group_id: age_group.id,
        seniority_id: seniority.id,
        role_id: 0,
        work_start_date: DateTime.now - 2.year - 3.month,
        office: o,
        job_title_id: 1,
      )
      Rank.create(id: 0, name: 'rank0')
      Role.create(company_id: 1, id: 0, name: 'role0')
    end
    it ', should return data as hash' do
      res = e.pack_to_json
      expect(res[:id]).to eq(e.id)
      expect(res[:email]).to eq(e.email)
      expect(res[:first_name]).to eq(e.first_name)
      expect(res[:last_name]).to eq(e.last_name)
      expect(res[:age_group]).to eq('25-34')
      expect(res[:group_name]).to eq(g.name)
      expect(res[:job_title]).to eq(e.job_title)
      expect(res[:rank]).to eq('rank0')
      expect(res[:gender]).to eq(e.gender)
      expect(res[:img_url]).to eq('/assets/missing_user.jpg')
      expect(res[:seniority]).to eq('2Y')
      expect(res[:office]).to eq(o.name)
    end
  end

  it ', Employee.by_company should return all employees of company' do
    n = rand(1..100)
    company_id = rand(1..5)
    counter = 0
    (1..n).each do |i|
      id = rand(1..5)
      FactoryBot.create(:employee,
                         first_name: "name_#{i}",
                         last_name: "name_#{i}",
                         email: "name_#{i}@company.com",
                         company_id: id)
      counter += 1 if company_id == id
    end
    expect((Employee.by_company company_id).count).to eq(counter)
  end

  it ', Creating employee with pin related attributes works' do
    emp_count = Employee.all.length
    FactoryBot.create(
      :employee,
      email: 'a@mail.com',
      first_name: 'A',
      last_name: 'A',
      company_id: 1,
      role_id: 1,
      rank_id: 1,
      gender: :female,
      marital_status_id: 1,
      qualifications: 1,
      employment: :full_time
    )
    expect(Employee.all.length).to be >= emp_count + 1
  end

  describe ', verify that given an employees we can find the pins it belongs to' do
    before do
      FactoryBot.create(:employee)
      FactoryBot.create_list(:pin, 2)
      EmployeesPin.create(pin_id: 1, employee_id: 1)
      EmployeesPin.create(pin_id: 2, employee_id: 1)

    end
    it ' should return a valid list of employees' do
      emp = Employee.find(1)
      pins = emp.pins
      expect(pins.length).to eq(2)
    end
  end

  describe 'build_from_hash' do
    describe 'should return hash object' do
      res = nil
      attrs = {
        company_id: 1,
        external_id: 1,
        first_name: 'aaa',
        last_name: 'bbb',
        email: 'some@email.com',
        delete: 'delete'
      }
      before do
        res = Employee.build_from_hash(attrs)
        res = res.keys
      end
      it 'hash[0] should be :employee' do
        expect(res[0]).to eq(:employee)
      end
      it 'hash[1] should be :alias_emails' do
        expect(res[1]).to eq(:alias_emails)
      end
      it 'hash[4] should be :group_name' do
        expect(res[4]).to eq(:marital_status)
      end
      it 'hash[9] should be :errors' do
        expect(res[9]).to eq(:errors)
      end
    end
  end

  describe 'create_snapshot in employee' do
    before do
      FactoryBot.create(:employee, role_id: 10)
      FactoryBot.create(:group, external_id: 'group-1',snapshot_id: 100)
      FactoryBot.create(:group, external_id: 'group-1',snapshot_id: 101)
    end

    it 'create without specifying a snapshot should create employee with snapshot_id -1' do
      expect(Employee.first.role_id).to eq(10)
      expect(Employee.first.snapshot_id).to eq(1)
    end

    it 'should create a new snapshot 100 from snapshot 1' do
      Employee.create_snapshot(1, 1, 100)
      expect(Employee.count).to eq(2)
      expect(Employee.last.snapshot_id).to eq(100)
    end

    it 'should do nothing if employees already exists in this snapshot' do
      Employee.create_snapshot(1, 1, 100)
      Employee.create_snapshot(1, 1, 100)
      expect(Employee.count).to eq(2)
      expect(Employee.first.snapshot_id).to eq(1)
      expect(Employee.last.snapshot_id).to eq(100)
    end

    it 'should create a new snapshot 101 from snapshot 100 with the change in role_id' do
      Employee.create_snapshot(1, 1, 100)
      Employee.where(snapshot_id: 100).update_all(role_id: 11)
      Employee.create_snapshot(1, 100, 101)
      expect(Employee.count).to eq(3)
      expect(Employee.last.snapshot_id).to eq(101)
      expect(Employee.last.role_id).to eq(11)
    end

    it 'should not copy over inactive employees to new snapshot' do
      FactoryBot.create(:employee, role_id: 10)
      Employee.last.update(active: false)
      Employee.create_snapshot(1, 1, 100)
      expect(Employee.count).to eq(3)
      expect(Employee.where(snapshot_id: 100).first.email).to eq('employee2@domain.com')
    end

    it 'should be assigned to the correct group' do
      Employee.create_snapshot(1, 1, 100)
      Employee.create_snapshot(1, 1, 101)
      expect(Employee.last.group_id).to eq(Group.last.id)
    end

    it 'should throw an exception if creating a snapshot which dont have groups yet' do
      expect{ Employee.create_snapshot(1, 1, 102) }.to raise_error(RuntimeError, 'Groups have to be bumped into new snapshot before employees')
    end

    describe 'id_in_snapshot' do
      emp = nil
      before do
        FactoryBot.create(:employee)
        FactoryBot.create(:employee)
        FactoryBot.create(:employee)
        emp = FactoryBot.create(:employee)
        Snapshot.create!(id: 100, company_id: 1, timestamp: Time.now + 1.week)
        Snapshot.create!(id: 101, company_id: 1, timestamp: Time.now + 2.weeks)
        Employee.create_snapshot(1, 1, 100)
        Employee.create_snapshot(1, 100, 101)
      end

      it 'should get correct new id' do
        emp2id = Employee.id_in_snapshot(emp.id, 100)
        emp2 = Employee.find(emp2id)
        expect(emp2.external_id).to eq(emp.external_id)
      end

      it 'should get id from last snapshot if none is given' do
        emp2id = Employee.id_in_snapshot(emp.id, 101)
        emp2   = Employee.find(emp2id)
        emp3id = Employee.id_in_snapshot(emp.id)
        emp3   = Employee.find(emp3id)
        expect(emp2.external_id).to eq(emp3.external_id)
        expect(emp3.snapshot_id).to eq(101)
      end
    end
  end
end
