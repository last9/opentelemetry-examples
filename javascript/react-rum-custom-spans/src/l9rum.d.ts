export {};

declare global {
  interface Window {
    L9RUM: {
      init(options: Record<string, unknown>): Promise<void>;
      sendTestEvent?: () => Promise<{ ok: boolean; status: number; error?: string }>;
    };
  }
}
