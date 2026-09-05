import React, { useEffect, useState } from 'react';
import { Elements } from '@stripe/react-stripe-js';
import { Stripe } from '@stripe/stripe-js';
import { CheckoutForm } from './components/CheckoutForm';
import { checkReturnFrom3DS, loadStripeWithTracing } from './stripe-instrumentation';

// Amount to charge in the smallest currency unit (e.g. cents for USD)
const AMOUNT = 2000;
const CURRENCY = 'usd';

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL || 'http://localhost:3001';
const STRIPE_PUBLISHABLE_KEY = process.env.REACT_APP_STRIPE_PUBLISHABLE_KEY || '';

const App: React.FC = () => {
  const [stripePromise, setStripePromise] = useState<Promise<Stripe | null> | null>(null);
  const [clientSecret, setClientSecret] = useState<string>('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Instrument loadStripe() so Stripe.js script load time appears in traces
    setStripePromise(loadStripeWithTracing(STRIPE_PUBLISHABLE_KEY));
  }, []);

  useEffect(() => {
    // Create a PaymentIntent on the backend and get the client_secret
    fetch(`${BACKEND_URL}/api/v1/payment_intents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount: AMOUNT, currency: CURRENCY }),
    })
      .then((res) => res.json())
      .then((data) => {
        if (data.error) {
          setError(data.error);
        } else {
          setClientSecret(data.client_secret);
        }
      })
      .catch(() => setError('Could not reach the payments backend.'));
  }, []);

  useEffect(() => {
    // Detect return from a 3DS redirect and emit traces/logs for the outcome.
    // Must run after stripePromise resolves.
    if (!stripePromise) return;
    stripePromise.then((stripe) => {
      if (stripe) checkReturnFrom3DS(stripe);
    });
  }, [stripePromise]);

  if (error) {
    return (
      <div style={styles.errorBox}>
        <strong>Error:</strong> {error}
      </div>
    );
  }

  if (!clientSecret || !stripePromise) {
    return <div style={styles.loading}>Loading checkout…</div>;
  }

  return (
    <Elements
      stripe={stripePromise}
      options={{
        clientSecret,
        appearance: { theme: 'stripe' },
      }}
    >
      <CheckoutForm amount={AMOUNT} currency={CURRENCY} />
    </Elements>
  );
};

const styles: Record<string, React.CSSProperties> = {
  loading: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    height: '100vh',
    fontSize: 16,
    color: '#6b7280',
    fontFamily: "'Inter', system-ui, sans-serif",
  },
  errorBox: {
    maxWidth: 460,
    margin: '40px auto',
    padding: 16,
    background: '#fef2f2',
    border: '1px solid #fca5a5',
    borderRadius: 6,
    color: '#b91c1c',
    fontFamily: "'Inter', system-ui, sans-serif",
  },
};

export default App;
