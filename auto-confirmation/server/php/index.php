<?php
use Slim\Http\Request;
use Slim\Http\Response;
use Stripe\Stripe;

require 'vendor/autoload.php';

if (PHP_SAPI == 'cli-server') {
  $_SERVER['SCRIPT_NAME'] = '/index.php';
}

$dotenv = Dotenv\Dotenv::create(realpath('../..'));
$dotenv->load();

$app = new \Slim\App;

// Instantiate the logger as a dependency
$container = $app->getContainer();
$container['logger'] = function ($c) {
  $settings = $c->get('settings')['logger'];
  $logger = new Monolog\Logger($settings['name']);
  $logger->pushProcessor(new Monolog\Processor\UidProcessor());
  $logger->pushHandler(new Monolog\Handler\StreamHandler(__DIR__ . '/logs/app.log', \Monolog\Logger::DEBUG));
  return $logger;
};

$app->add(function ($request, $response, $next) {
    Stripe::setApiKey(getenv('STRIPE_SECRET_KEY'));
    return $next($request, $response);
});
$app->get('/css/normalize.css', function (Request $request, Response $response, array $args) { 
  return $response->withHeader('Content-Type', 'text/css')->write(file_get_contents('../../client/css/normalize.css'));
});
$app->get('/css/global.css', function (Request $request, Response $response, array $args) { 
  return $response->withHeader('Content-Type', 'text/css')->write(file_get_contents('../../client/css/global.css'));
});
$app->get('/script.js', function (Request $request, Response $response, array $args) { 
  return $response->withHeader('Content-Type', 'text/javascript')->write(file_get_contents('../../client/script.js'));
});


$app->get('/', function (Request $request, Response $response, array $args) {   
  // Display checkout page
  return $response->write(file_get_contents('../../client/index.html'));
});

function calculateOrderAmount($items)
{
  // Replace this constant with a calculation of the order's amount
  // Calculate the order total on the server to prevent
  // people from directly manipulating the amount on the client
  return 1400;
}

$app->post('/create-payment-intent', function (Request $request, Response $response, array $args) {
    $pub_key = getenv('STRIPE_PUBLIC_KEY');
    $body = json_decode($request->getBody());

    // Create a PaymentIntent with the order amount and currency
    $payment_intent = \Stripe\PaymentIntent::create([
      "amount" => calculateOrderAmount($body->items),
      "currency" => $body->currency,
      "capture_method" => "manual"
    ]);
    
    // Send public key and PaymentIntent details to client
    return $response->withJson(array('publicKey' => $pub_key, 'clientSecret' => $payment_intent->client_secret, 'id' => $payment_intent->id));
});

$app->post('/webhook', function(Request $request, Response $response) {
    $logger = $this->get('logger');
    $event = $request->getParsedBody();
    // Parse the message body (and check the signature if possible)
    $webhookSecret = getenv('STRIPE_WEBHOOK_SECRET');
    if ($webhookSecret) {
      try {
        $event = \Stripe\Webhook::constructEvent(
          $request->getBody(),
          $request->getHeaderLine('stripe-signature'),
          $webhookSecret
        );
      } catch (\Exception $e) {
        return $response->withJson([ 'error' => $e->getMessage() ])->withStatus(403);
      }
    } else {
      $event = $request->getParsedBody();
    }
    $type = $event['type'];
    $object = $event['data']['object'];
    
    if ($type == 'payment_intent.amount_capturable_updated') {
      // You can capture an amount less than or equal to the amount_capturable
      // By default capture() will capture the full amount_capturable
      // To cancel a payment before capturing use .cancel() (https://stripe.com/docs/api/payment_intents/cancel)
      $intent = \Stripe\PaymentIntent::retrieve($object->id);
      $logger->info('❗ Charging the card for: ' . $intent->amount_capturable);
      $intent->capture();
    } else if ($type == 'payment_intent.succeeded') {
      // Fulfill any orders, e-mail receipts, etc
      // To cancel the payment after capture you will need to issue a Refund (https://stripe.com/docs/api/refunds)
      $logger->info('💰 Payment received! ');
    } else if ($type == 'payment_intent.payment_failed') {
      $logger->info('❌ Payment failed.');
    }

    return $response->withJson([ 'status' => 'success' ])->withStatus(200);
});

$app->run();
