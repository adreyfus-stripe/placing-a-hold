require 'stripe'
require 'sinatra'
require 'dotenv'

Dotenv.load(File.dirname(__FILE__) + '/../../.env')
Stripe.api_key = ENV['STRIPE_SECRET_KEY']

set :static, true
set :public_folder, File.join(File.dirname(__FILE__), '../../client/')
set :port, 4242

get '/' do
  # Display checkout page
  content_type 'text/html'
  send_file File.join(settings.public_folder, 'index.html')
end

def calculate_order_amount(_items)
  # Replace this constant with a calculation of the order's amount
  # Calculate the order total on the server to prevent
  # people from directly manipulating the amount on the client
  1400
end

post '/create-payment-intent' do
  content_type 'application/json'
  data = JSON.parse(request.body.read)

  # Create a PaymentIntent with the order amount and currency
  payment_intent = Stripe::PaymentIntent.create(
    amount: calculate_order_amount(data['items']),
    currency: data['currency'],
    capture_method: 'manual'
  )

  # Send public key and PaymentIntent details to client
  {
    publicKey: ENV['STRIPE_PUBLIC_KEY'],
    clientSecret: payment_intent['client_secret'],
    id: payment_intent['id']
  }.to_json
end

post '/webhook' do
  # Use webhooks to receive information about asynchronous payment events.
  # For more about our webhook events check out https://stripe.com/docs/webhooks.
  webhook_secret = ENV['STRIPE_WEBHOOK_SECRET']
  payload = request.body.read
  if !webhook_secret.empty?
    # Retrieve the event by verifying the signature using the raw body and secret if webhook signing is configured.
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    event = nil

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, webhook_secret
      )
    rescue JSON::ParserError => e
      # Invalid payload
      status 400
      return
    rescue Stripe::SignatureVerificationError => e
      # Invalid signature
      puts '⚠️  Webhook signature verification failed.'
      status 400
      return
    end
  else
    data = JSON.parse(payload, symbolize_names: true)
    event = Stripe::Event.construct_from(data)
  end
  # Get the type of webhook event sent - used to check the status of PaymentIntents.
  event_type = event['type']
  data = event['data']
  data_object = data['object']

  if event_type == 'payment_intent.amount_capturable_updated'
    puts '❗ Charging the card for: ' + data_object['amount_capturable'].to_s
    # You can capture an amount less than or equal to the amount_capturable
    # By default capture() will capture the full amount_capturable
    # To cancel a payment before capturing use .cancel() (https://stripe.com/docs/api/payment_intents/cancel)
    intent = Stripe::PaymentIntent.capture(data_object['id'])
  elsif event_type == 'payment_intent.succeeded'
    puts '💰 Payment received!'
    # Fulfill any orders, e-mail receipts, etc
    # To cancel the payment after capture you will need to issue a Refund (https://stripe.com/docs/api/refunds)
  elsif event_type == 'payment_intent.payment_failed'
    puts '❌ Payment failed.'
  end

  content_type 'application/json'
  {
    status: 'success'
  }.to_json
end
