// utils.js

/**
 * Check if the interface is virtual..
 */
export const isVirtualIface = (name, virtualIfacePrefixes) => {
    return virtualIfacePrefixes.some(prefix => name.startsWith(prefix));
};

/**
 * Format speed with appropriate unit.
 */
export const formatSpeedWithUnit = (amount, speedUnits) => {
    let unitIndex = 0;
    while (amount >= 1000 && unitIndex < speedUnits.length - 1) {
        amount /= 1000;
        ++unitIndex;
    }

    const digits = amount >= 100 || amount - 0 < 0.01 ? 0 : amount >= 10 ? 1 : 2;
    return `${amount.toFixed(digits)} ${speedUnits[unitIndex]}`;
};

/**
 * Convert speed object to string.
 */
export const toSpeedString = (speed, speedUnits) => {
    return `↓ ${formatSpeedWithUnit(speed.down, speedUnits)} ↑ ${formatSpeedWithUnit(speed.up, speedUnits)}`;
};