# == Schema Information
#
# Table name: payment_notifications
#
#  id                :integer          not null, primary key
#  type              :string(255)      not null
#  txn_id            :string(255)      not null
#  raw_post          :text
#  order_id          :integer
#  created_at        :datetime
#  updated_at        :datetime
#  secret_matched    :boolean
#  payment_method_id :integer
#  raw_json          :json
#
# Indexes
#
#  index_payment_notifications_on_order_id  (order_id)
#  index_payment_notifications_on_txn_id    (txn_id)
#  index_payment_notifications_on_type      (type)
#

require 'spec_helper'

describe PaymentNotification::Paypal do

  let!(:person) { create(:person) }
  let(:cart) { person.shopping_cart }

  let(:txn_id) { '9HV21269FCK60249' }
  let(:payment_status) { 'Completed' }
  let(:payment_type) { 'instant' }
  let(:handling_amount) { 0.0 }
  let(:mc_fee) { 0.25 }
  let(:mc_gross) { 25.25 }

  let(:post_data) do
    {"business"=>Api::Application.config.paypal[:email],
     "charset"=>"windows-1252",
     "first_name"=>person.first_name,
     "handling_amount"=>handling_amount,
     "ipn_track_id"=>"3b8902618903",
     "item_name"=>"Bountysource Order #1",
     "item_number"=>cart.id,
     "last_name"=>person.last_name,
     "mc_currency"=>"USD",
     "mc_fee"=>mc_fee,
     "mc_gross"=>mc_gross,
     "notify_version"=>"3.7",
     "payer_email"=>person.email,
     "payer_id"=>"WESLTEG56ZUT8",
     "payer_status"=>"verified",
     "payment_date"=>1.minute.ago,
     "payment_fee"=>"0.88",
     "payment_gross"=>"20.00",
     "payment_status"=>payment_status,
     "payment_type"=>payment_type,
     "protection_eligibility"=>"Ineligible",
     "quantity"=>"1",
     "receiver_email"=>person.email,
     "receiver_id"=>"J6F3EFZTLH5JW",
     "residence_country"=>"US",
     "shipping"=>"0.00",
     "tax"=>"0.00",
     "test_ipn"=>"1",
     "transaction_subject"=>"oh hi",
     "txn_id"=>txn_id,
     "txn_type"=>"web_accept",
     "verify_sign"=>"AHy.ZmQnHLBY5C6.kl669Ql4MnrqAAuUuj-MQprK.dgzOgGVZpk4dGe-"}
  end

  let(:process_post) { -> (data=post_data) { PaymentNotification::Paypal.process_raw_post data.to_param } }

  it 'should have txn_id in params' do
    response = process_post[]
    response.params['txn_id'].should be == txn_id
  end

  it 'should load shopping cart' do
    process_post[].shopping_cart.should be == cart
  end

  it 'should load person' do
    process_post[].person.should be == person
  end

  describe 'completed status' do
    let(:payment_status) { 'Completed' }

    it 'should be completed' do
      process_post[].should be_completed
    end
  end

  describe 'pending status' do
    let(:payment_status) { 'Pending' }

    it 'should be pending' do
      process_post[].should be_pending
    end
  end

  describe 'instant payment' do
    let(:payment_type) { 'instant' }

    it 'should be instant payment' do
      process_post[].should be_instant
    end
  end

  describe 'echeck' do
    let(:payment_type) { 'echeck' }

    it 'should be echeck' do
      process_post[].should be_echeck
    end
  end

  describe 'verification' do

    it 'should not verify if cart gross does not match' do
      response = process_post[]
      response.params['mc_gross'] = '1.0'
      response.should_not be_verified
    end

    it 'should not verify if business email does not match' do
      response = process_post[]
      response.params['business'] = nil
      response.should_not be_verified
    end

    it 'should not verify if post back fails' do
      response = process_post[]
      response.stub(:post_back) { 'POSTBACK' }
      response.should_not be_verified
    end

    it 'should only verify in status is Completed' do
      response = process_post[]
      response.params['payment_status'] = 'Denied'
      response.should_not be_verified
    end

    it 'should only verify if instant or echeck' do
      response = process_post[]
      response.params['payment_type'] = 'FAKE'
      response.should_not be_verified
    end

    it 'should verify instant' do
      response = process_post[]
      response.params['payment_status'] = 'Completed'
      response.params['payment_type'] = 'instant'
      ShoppingCart.any_instance.stub(:calculate_gross) { response.params['mc_gross'].to_f }
      response.params['business'] = Api::Application.config.paypal[:email]
      response.stub(:post_back) { 'VERIFIED' }
      response.should be_verified
    end

    it 'should verify echeck' do
      response = process_post[]
      response.params['payment_status'] = 'Completed'
      response.params['payment_type'] = 'echeck'
      ShoppingCart.any_instance.stub(:calculate_gross) { response.params['mc_gross'].to_f }
      response.params['business'] = Api::Application.config.paypal[:email]
      response.stub(:post_back) { 'VERIFIED' }
      response.should be_verified
    end

  end

  describe 'verified' do

    let(:response) do
      response = process_post[]
      response.stub(:verified?) { true }
      response
    end

    it 'should create PaymentNotification' do
      expect {
        PaymentNotification.any_instance.stub(:verified?) { true }
        process_post[]
      }.to change(PaymentNotification::Paypal, :count).by 1
    end

  end

  it 'should not create Transaction by processing PaymentNotification' do
    expect {
      process_post[]
    }.not_to change(Transaction, :count)
  end

end
