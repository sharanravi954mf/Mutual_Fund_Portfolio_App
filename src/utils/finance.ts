/**
 * Calculates absolute return percentage.
 * 
 * Formula: ((Current Value - Invested Value) / Invested Value) * 100
 */
export function calculateAbsoluteReturn(invested: number, current: number): number {
  if (invested <= 0) return 0;
  return ((current - invested) / invested) * 100;
}

export interface CashFlow {
  amount: number; // Negative for investments (cash outflow), positive for returns/current valuation (cash inflow)
  date: Date;
}

/**
 * Calculates the Internal Rate of Return for irregular cash flows (XIRR).
 * Uses the Newton-Raphson root-finding method.
 * 
 * Formula to solve for r: Sum(C_i / (1 + r)^((d_i - d_1) / 365)) = 0
 * 
 * @param cashFlows List of cash flows with amounts and dates.
 * @param guess Initial guess for rate (default: 0.1 for 10%).
 * @returns Annualized rate of return as a percentage (e.g. 15.5 for 15.5%).
 */
export function calculateXIRR(cashFlows: CashFlow[], guess: number = 0.1): number {
  if (cashFlows.length < 2) return 0;

  // Sort chronologically
  const sorted = [...cashFlows].sort((a, b) => a.date.getTime() - b.date.getTime());
  const d0 = sorted[0].date.getTime();

  // Function f(r)
  const f = (r: number): number => {
    let sum = 0;
    for (const cf of sorted) {
      const days = (cf.date.getTime() - d0) / (1000 * 60 * 60 * 24);
      sum += cf.amount / Math.pow(1 + r, days / 365);
    }
    return sum;
  };

  // Derivative f'(r)
  const df = (r: number): number => {
    let sum = 0;
    for (const cf of sorted) {
      const days = (cf.date.getTime() - d0) / (1000 * 60 * 60 * 24);
      sum += - (days / 365) * cf.amount / Math.pow(1 + r, (days / 365) + 1);
    }
    return sum;
  };

  let r = guess;
  const tolerance = 1e-6;
  const maxIterations = 100;

  for (let i = 0; i < maxIterations; i++) {
    const val = f(r);
    const deriv = df(r);

    if (Math.abs(deriv) < 1e-12) {
      break; // Prevent division by zero
    }

    const nextR = r - val / deriv;

    if (Math.abs(nextR - r) < tolerance) {
      return nextR * 100; // Convert to percentage
    }

    r = nextR;
  }

  return r * 100; // Fallback to last calculated rate
}
