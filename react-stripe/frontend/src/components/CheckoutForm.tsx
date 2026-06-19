import React, { useEffect, useRef, useState } from 'react';
import { PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { recordElementsMount, traceStripePayment } from '../stripe-instrumentation';

interface CheckoutFormProps {
  amount: number;
  currency: string;
}

export const CheckoutForm: React.FC<CheckoutFormProps> = ({ amount, currency }) => {
  const stripe = useStripe();
  const elements = useElements();

  const [message, setMessage] = useState<string | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [succeeded, setSucceeded] = useState(false);

  // Record when we started rendering the form so we can measure mount time
  const mountStartRef = useRef<number>(Date.now());

  const handleReady = () => {
    // PaymentElement fires onReady when the card input is fully rendered
    recordElementsMount(mountStartRef.current);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!stripe || !elements) return;

    setIsProcessing(true);
    setMessage(null);

    const { error } = await traceStripePayment(stripe, elements, {
      amount,
      currency,
      returnUrl: `${window.location.origin}?payment_intent_client_secret=`,
    });

    if (error) {
      setMessage(error.message ?? 'An unexpected error occurred.');
    } else {
      setSucceeded(true);
      setMessage('Payment succeeded!');
    }

    setIsProcessing(false);
  };

  if (succeeded) {
    return (
      <div style={styles.success}>
        <h2>Payment successful</h2>
        <p>
          Amount charged: {(amount / 100).toFixed(2)} {currency.toUpperCase()}
        </p>
        <p style={styles.hint}>
          Check your Last9 dashboard — traces and logs for this payment are on
          their way.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} style={styles.form}>
      <h2 style={styles.heading}>Complete your payment</h2>

      <div style={styles.amount}>
        {(amount / 100).toFixed(2)} {currency.toUpperCase()}
      </div>

      <PaymentElement onReady={handleReady} />

      <button
        type="submit"
        disabled={!stripe || isProcessing}
        style={isProcessing ? { ...styles.button, ...styles.buttonDisabled } : styles.button}
      >
        {isProcessing ? 'Processing…' : 'Pay now'}
      </button>

      {message && (
        <p style={succeeded ? styles.messageSuccess : styles.messageError}>
          {message}
        </p>
      )}
    </form>
  );
};

const styles: Record<string, React.CSSProperties> = {
  form: {
    maxWidth: 460,
    margin: '40px auto',
    padding: 32,
    background: '#fff',
    borderRadius: 8,
    boxShadow: '0 2px 12px rgba(0,0,0,0.1)',
    fontFamily: "'Inter', system-ui, sans-serif",
  },
  heading: {
    marginTop: 0,
    marginBottom: 8,
    fontSize: 20,
    color: '#1a1a2e',
  },
  amount: {
    fontSize: 28,
    fontWeight: 700,
    color: '#635bff',
    marginBottom: 24,
  },
  button: {
    marginTop: 20,
    width: '100%',
    padding: '12px 0',
    fontSize: 16,
    fontWeight: 600,
    color: '#fff',
    background: '#635bff',
    border: 'none',
    borderRadius: 6,
    cursor: 'pointer',
  },
  buttonDisabled: {
    opacity: 0.6,
    cursor: 'not-allowed',
  },
  messageError: {
    marginTop: 12,
    color: '#df1b41',
    fontSize: 14,
  },
  messageSuccess: {
    marginTop: 12,
    color: '#1a7f5a',
    fontSize: 14,
  },
  success: {
    maxWidth: 460,
    margin: '40px auto',
    padding: 32,
    background: '#f0fdf4',
    borderRadius: 8,
    textAlign: 'center',
  },
  hint: {
    fontSize: 13,
    color: '#6b7280',
    marginTop: 12,
  },
};
