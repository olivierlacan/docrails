# encoding: utf-8
require 'cases/helper'
require 'cases/tests_database'

require 'models/topic'
require 'models/reply'
require 'models/developer'
require 'models/custom_reader'

class ValidationsTest < ActiveModel::TestCase
  include ActiveModel::TestsDatabase

  def setup
    Topic._validators.clear
  end

  # Most of the tests mess with the validations of Topic, so lets repair it all the time.
  # Other classes we mess with will be dealt with in the specific tests
  def teardown
    Topic.reset_callbacks(:validate)
  end

  def test_single_field_validation
    r = Reply.new
    r.title = "There's no content!"
    assert r.invalid?, "A reply without content shouldn't be saveable"

    r.content = "Messa content!"
    assert r.valid?, "A reply with content should be saveable"
  end

  def test_single_attr_validation_and_error_msg
    r = Reply.new
    r.title = "There's no content!"
    assert r.invalid?
    assert r.errors[:content].any?, "A reply without content should mark that attribute as invalid"
    assert_equal ["is Empty"], r.errors["content"], "A reply without content should contain an error"
    assert_equal 1, r.errors.count
  end

  def test_double_attr_validation_and_error_msg
    r = Reply.new
    assert r.invalid?

    assert r.errors[:title].any?, "A reply without title should mark that attribute as invalid"
    assert_equal ["is Empty"], r.errors["title"], "A reply without title should contain an error"

    assert r.errors[:content].any?, "A reply without content should mark that attribute as invalid"
    assert_equal ["is Empty"], r.errors["content"], "A reply without content should contain an error"

    assert_equal 2, r.errors.count
  end

  def test_single_error_per_attr_iteration
    r = Reply.new
    r.valid?

    errors = []
    r.errors.each {|attr, messages| errors << [attr.to_s, messages] }

    assert errors.include?(["title", "is Empty"])
    assert errors.include?(["content", "is Empty"])
  end

  def test_multiple_errors_per_attr_iteration_with_full_error_composition
    r = Reply.new
    r.title   = ""
    r.content = ""
    r.valid?

    errors = r.errors.to_a

    assert_equal "Content is Empty", errors[0]
    assert_equal "Title is Empty", errors[1]
    assert_equal 2, r.errors.count
  end

  def test_errors_on_nested_attributes_expands_name
    t = Topic.new
    t.errors["replies.name"] << "can't be blank"
    assert_equal ["Replies name can't be blank"], t.errors.full_messages
  end

  def test_errors_on_base
    r = Reply.new
    r.content = "Mismatch"
    r.valid?
    r.errors[:base] << "Reply is not dignifying"

    errors = []
    r.errors.to_a.each { |error| errors << error }

    assert_equal ["Reply is not dignifying"], r.errors[:base]

    assert errors.include?("Title is Empty")
    assert errors.include?("Reply is not dignifying")
    assert_equal 2, r.errors.count
  end

  def test_errors_empty_after_errors_on_check
    t = Topic.new
    assert t.errors[:id].empty?
    assert t.errors.empty?
  end

  def test_validates_each
    hits = 0
    Topic.validates_each(:title, :content, [:title, :content]) do |record, attr|
      record.errors.add attr, 'gotcha'
      hits += 1
    end
    t = Topic.new("title" => "valid", "content" => "whatever")
    assert t.invalid?
    assert_equal 4, hits
    assert_equal %w(gotcha gotcha), t.errors[:title]
    assert_equal %w(gotcha gotcha), t.errors[:content]
  end

  def test_validates_each_custom_reader
    hits = 0
    CustomReader.validates_each(:title, :content, [:title, :content]) do |record, attr|
      record.errors.add attr, 'gotcha'
      hits += 1
    end
    t = CustomReader.new("title" => "valid", "content" => "whatever")
    assert t.invalid?
    assert_equal 4, hits
    assert_equal %w(gotcha gotcha), t.errors[:title]
    assert_equal %w(gotcha gotcha), t.errors[:content]
  end

  def test_validate_block
    Topic.validate { |topic| topic.errors.add("title", "will never be valid") }
    t = Topic.new("title" => "Title", "content" => "whatever")
    assert t.invalid?
    assert t.errors[:title].any?
    assert_equal ["will never be valid"], t.errors["title"]
  end

  def test_invalid_validator
    Topic.validate :i_dont_exist
    assert_raise(NameError) do
      t = Topic.new
      t.valid?
    end
  end

  def test_errors_to_xml
    r = Reply.new :title => "Wrong Create"
    assert r.invalid?
    xml = r.errors.to_xml(:skip_instruct => true)
    assert_equal "<errors>", xml.first(8)
    assert xml.include?("<error>Content is Empty</error>")
  end

  def test_validation_order
    Topic.validates_presence_of :title
    Topic.validates_length_of :title, :minimum => 2

    t = Topic.new("title" => "")
    assert t.invalid?
    assert_equal "can't be blank", t.errors["title"].first
    Topic.validates_presence_of :title, :author_name
    Topic.validate {|topic| topic.errors.add('author_email_address', 'will never be valid')}
    Topic.validates_length_of :title, :content, :minimum => 2

    t = Topic.new :title => ''
    assert t.invalid?

    assert_equal :title, key = t.errors.keys.first
    assert_equal "can't be blank", t.errors[key].first
    assert_equal 'is too short (minimum is 2 characters)', t.errors[key].second
    assert_equal :author_name, key = t.errors.keys.second
    assert_equal "can't be blank", t.errors[key].first
    assert_equal :author_email_address, key = t.errors.keys.third
    assert_equal 'will never be valid', t.errors[key].first
    assert_equal :content, key = t.errors.keys.fourth
    assert_equal 'is too short (minimum is 2 characters)', t.errors[key].first
  end

  def test_invalid_should_be_the_opposite_of_valid
    Topic.validates_presence_of :title

    t = Topic.new
    assert t.invalid?
    assert t.errors[:title].any?

    t.title = 'Things are going to change'
    assert !t.invalid?
  end

  def test_deprecated_error_messages_on
    Topic.validates_presence_of :title

    t = Topic.new
    assert t.invalid?

    [:title, "title"].each do |attribute|
      assert_deprecated { assert_equal "can't be blank", t.errors.on(attribute) }
    end

    Topic.validates_each(:title) do |record, attribute|
      record.errors[attribute] << "invalid"
    end

    assert t.invalid?

    [:title, "title"].each do |attribute|
      assert_deprecated do
        assert t.errors.on(attribute).include?("invalid")
        assert t.errors.on(attribute).include?("can't be blank")
      end
    end
  end

  def test_deprecated_errors_on_base_and_each
    t = Topic.new
    assert t.valid?

    assert_deprecated { t.errors.add_to_base "invalid topic" }
    assert_deprecated { assert_equal "invalid topic", t.errors.on_base }
    assert_deprecated { assert t.errors.invalid?(:base) }

    all_errors = t.errors.to_a
    assert_deprecated { assert_equal all_errors, t.errors.each_full{|err| err} }
  end

  def test_validation_with_message_as_proc
    Topic.validates_presence_of(:title, :message => proc { "no blanks here".upcase })

    t = Topic.new
    assert t.invalid?
    assert ["NO BLANKS HERE"], t.errors[:title]
  end

  def test_list_of_validators_for_model
    Topic.validates_presence_of :title
    Topic.validates_length_of :title, :minimum => 2

    assert_equal 2, Topic.validators.count
    assert_equal [:presence, :length], Topic.validators.map(&:kind)
  end

  def test_list_of_validators_on_an_attribute
    Topic.validates_presence_of :title, :content
    Topic.validates_length_of :title, :minimum => 2

    assert_equal 2, Topic.validators_on(:title).count
    assert_equal [:presence, :length], Topic.validators_on(:title).map(&:kind)
    assert_equal 1, Topic.validators_on(:content).count
    assert_equal [:presence], Topic.validators_on(:content).map(&:kind)
  end

  def test_accessing_instance_of_validator_on_an_attribute
    Topic.validates_length_of :title, :minimum => 10
    assert_equal 10, Topic.validators_on(:title).first.options[:minimum]
  end
end
