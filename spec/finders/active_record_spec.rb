require 'spec_helper'
require 'will_paginate/finders/active_record'
require File.dirname(__FILE__) + '/activerecord_test_connector'

class ArProject < ActiveRecord::Base
end

ActiverecordTestConnector.setup

describe WillPaginate::Finders::ActiveRecord do
  
  def self.fixtures(*tables)
    table_names = tables.map { |t| t.to_s }
    
    fixtures = Fixtures.create_fixtures ActiverecordTestConnector::FIXTURES_PATH, table_names
    @@loaded_fixtures = {}
    @@fixture_cache = {}
    
    unless fixtures.nil?
      if fixtures.instance_of?(Fixtures)
        @@loaded_fixtures[fixtures.table_name] = fixtures
      else
        fixtures.each { |f| @@loaded_fixtures[f.table_name] = f }
      end
    end
    
    table_names.each do |table_name|
      define_method(table_name) do |*fixtures|
        @@fixture_cache[table_name] ||= {}

        instances = fixtures.map do |fixture|
          if @@loaded_fixtures[table_name][fixture.to_s]
            @@fixture_cache[table_name][fixture] ||= @@loaded_fixtures[table_name][fixture.to_s].find
          else
            raise StandardError, "No fixture with name '#{fixture}' found for table '#{table_name}'"
          end
        end

        instances.size == 1 ? instances.first : instances
      end
    end
  end
  
  it "should integrate with ActiveRecord::Base" do
    ActiveRecord::Base.should respond_to(:paginate)
  end
  
  it "should paginate" do
    ArProject.expects(:find).with(:all, { :limit => 5, :offset => 0 }).returns([])
    ArProject.paginate(:page => 1, :per_page => 5)
  end
  
  it "should respond to paginate_by_sql" do
    ArProject.should respond_to(:paginate_by_sql)
  end
  
  it "should support explicit :all argument" do
    ArProject.expects(:find).with(:all, instance_of(Hash)).returns([])
    ArProject.paginate(:all, :page => nil)
  end
  
  it "should put implicit all in dynamic finders" do
    ArProject.expects(:find_all_by_foo).returns([])
    ArProject.expects(:count).returns(0)
    ArProject.paginate_by_foo :page => 2
  end
  
  it "should leave extra parameters intact" do
    ArProject.expects(:find).with(:all, {:foo => 'bar', :limit => 4, :offset => 0 }).returns(Array.new(5))
    ArProject.expects(:count).with({:foo => 'bar'}).returns(1)

    ArProject.paginate :foo => 'bar', :page => 1, :per_page => 4
  end

  describe "counting" do
    it "should ignore nil in :count parameter" do
      ArProject.expects(:find).returns([])
      lambda { ArProject.paginate :page => nil, :count => nil }.should_not raise_error
    end
    
    it "should guess the total count" do
      ArProject.expects(:find).returns(Array.new(2))
      ArProject.expects(:count).never

      result = ArProject.paginate :page => 2, :per_page => 4
      result.total_entries.should == 6
    end

    it "should guess that there are no records" do
      ArProject.expects(:find).returns([])
      ArProject.expects(:count).never

      result = ArProject.paginate :page => 1, :per_page => 4
      result.total_entries.should == 0
    end
  end
  
  it "should not ignore :select parameter when it says DISTINCT" do
    ArProject.stubs(:find).returns([])
    ArProject.expects(:count).with(:select => 'DISTINCT salary').returns(0)
    ArProject.paginate :select => 'DISTINCT salary', :page => 2
  end

  it "should use :with_foo for scope-out compatibility" do
    ArProject.expects(:find_best).returns(Array.new(5))
    ArProject.expects(:with_best).returns(1)
    
    ArProject.paginate_best :page => 1, :per_page => 4
  end

  describe "paginate_by_sql" do
    it "should paginate" do
      ArProject.expects(:find_by_sql).with(regexp_matches(/sql LIMIT 3(,| OFFSET) 3/)).returns([])
      ArProject.expects(:count_by_sql).with('SELECT COUNT(*) FROM (sql) AS count_table').returns(0)
    
      ArProject.paginate_by_sql 'sql', :page => 2, :per_page => 3
    end

    it "should respect total_entrier setting" do
      ArProject.expects(:find_by_sql).returns([])
      ArProject.expects(:count_by_sql).never
    
      entries = ArProject.paginate_by_sql 'sql', :page => 1, :total_entries => 999
      entries.total_entries.should == 999
    end

    it "should strip the order when counting" do
      ArProject.expects(:find_by_sql).returns([])
      ArProject.expects(:count_by_sql).with("SELECT COUNT(*) FROM (sql\n ) AS count_table").returns(0)
    
      ArProject.paginate_by_sql "sql\n ORDER\nby foo, bar, `baz` ASC", :page => 2
    end
  end

  # TODO: counts would still be wrong!
  it "should be able to paginate custom finders" do
    # acts_as_taggable defines find_tagged_with(tag, options)
    ArProject.expects(:find_tagged_with).with('will_paginate', :offset => 5, :limit => 5).returns([])
    ArProject.expects(:count).with({}).returns(0)
    
    ArProject.paginate_tagged_with 'will_paginate', :page => 2, :per_page => 5
  end

  it "should not skip count when given an array argument to a finder" do
    ids = (1..8).to_a
    ArProject.expects(:find_all_by_id).returns([])
    ArProject.expects(:count).returns(0)
    
    ArProject.paginate_by_id(ids, :per_page => 3, :page => 2, :order => 'id')
  end

  it "doesn't mangle options" do
    ArProject.expects(:find).returns([])
    options = { :page => 1 }
    options.expects(:delete).never
    options_before = options.dup
    
    ArProject.paginate(options)
    options.should == options_before
  end
  
  if ActiverecordTestConnector.able_to_connect
    fixtures :topics, :replies, :users, :projects, :developers_projects
    
    it "should get first page of Topics with a single query" do
      lambda {
        result = Topic.paginate :page => nil
        result.current_page.should == 1
        result.total_pages.should == 1
        result.size.should == 4
      }.should run_queries
    end
    
    it "should get second (inexistent) page of Topics, requiring 2 queries" do
      lambda {
        result = Topic.paginate :page => 2
        result.total_pages.should == 1
        result.should be_empty
      }.should run_queries(2)
    end
    
    it "should paginate with :order" do
      result = Topic.paginate :page => 1, :order => 'created_at DESC'
      result.should == topics(:futurama, :harvey_birdman, :rails, :ar).reverse
      result.total_pages.should == 1
    end
    
    it "should paginate with :conditions" do
      result = Topic.paginate :page => 1, :conditions => ["created_at > ?", 30.minutes.ago]
      result.should == topics(:rails, :ar)
      result.total_pages.should == 1
    end

    it "should paginate with :include and :conditions" do
      result = Topic.paginate \
        :page     => 1, 
        :include  => :replies,  
        :conditions => "replies.content LIKE 'Bird%' ", 
        :per_page => 10

      expected = Topic.find :all, 
        :include => 'replies', 
        :conditions => "replies.content LIKE 'Bird%' ", 
        :limit   => 10

      result.should == expected
      result.total_entries.should == 1
    end

    it "should paginate with :include and :order" do
      result = nil
      lambda {
        result = Topic.paginate \
          :page     => 1, 
          :include  => :replies,  
          :order    => 'replies.created_at asc, topics.created_at asc', 
          :per_page => 10
      }.should run_queries(2)

      expected = Topic.find :all, 
        :include => 'replies', 
        :order   => 'replies.created_at asc, topics.created_at asc', 
        :limit   => 10

      result.should == expected
      result.total_entries.should == 4
    end
    
    # detect ActiveRecord 2.1
    if ActiveRecord::Base.private_methods.include?('references_eager_loaded_tables?')
      it "should remove :include for count" do
        Developer.expects(:find).returns([1])
        Developer.expects(:count).with({}).returns(0)
    
        Developer.paginate :page => 1, :per_page => 1, :include => :projects
      end
    
      it "should keep :include for count when they are referenced in :conditions" do
        Developer.expects(:find).returns([1])
        Developer.expects(:count).with({ :include => :projects, :conditions => 'projects.id > 2' }).returns(0)
    
        Developer.paginate :page => 1, :per_page => 1,
          :include => :projects, :conditions => 'projects.id > 2'
      end
    end
  end
  
  protected
  
    def run_queries(num = 1)
      QueryCountMatcher.new(num)
    end

end

class QueryCountMatcher
  def initialize(num)
    @queries = num
    @old_query_count = $query_count
  end

  def matches?(block)
    block.call
    @queries_run = $query_count - @old_query_count
    @queries == @queries_run
  end

  def failure_message
    "expected #{@queries} queries, got #{@queries_run}"
  end

  def negative_failure_message
    "expected query count not to be #{$queries}"
  end
end