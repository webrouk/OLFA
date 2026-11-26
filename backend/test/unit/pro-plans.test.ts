import { describe, expect, it } from 'vitest';
import { audienceOf, compareDirectory, decodeDirectoryCursor, encodeDirectoryCursor, insightsSummary, planFitsAccount } from '../../src/domain/pro-plans';
import { classifyChange } from '../../src/domain/store-subscriptions';

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;

describe('counselor plans', () => {
  it('member plans for members, counselor plans for professionals', () => {
    expect(planFitsAccount('PROFESSIONAL', 'PSYCHOLOGIST')).toBe(true);
    expect(planFitsAccount('PROFESSIONAL', 'FAMILY_COUNSELOR')).toBe(true);
    expect(planFitsAccount('PROFESSIONAL', 'MEMBER')).toBe(false);
    expect(planFitsAccount('MEMBER', 'PSYCHOLOGIST')).toBe(false);
    expect(planFitsAccount('MEMBER', 'MEMBER')).toBe(true);
    expect(audienceOf('FAMILY_COUNSELOR')).toBe('PROFESSIONAL');
    expect(audienceOf('MEMBER')).toBe('MEMBER');
  });

  it('directory cursor round-trips and rejects junk', () => {
    const k = { boost: 2, rating: 4.75, count: 31, id: id(7) };
    expect(decodeDirectoryCursor(encodeDirectoryCursor(k))).toEqual(k);
    expect(decodeDirectoryCursor(undefined)).toBeNull();
    expect(decodeDirectoryCursor(id(7))).toBeNull(); // old-style cursor → from the top
    expect(decodeDirectoryCursor(Buffer.from(`3|4|1|${id(1)}`).toString('base64url'))).toBeNull();
    expect(decodeDirectoryCursor(Buffer.from(`1|9|1|${id(1)}`).toString('base64url'))).toBeNull();
  });

  it('directory order: Premium, then Plus, then rating, ratings count, id', () => {
    const rows = [
      { boost: 0, rating: 5, count: 90, id: id(1) },
      { boost: 1, rating: 4.1, count: 3, id: id(2) },
      { boost: 2, rating: 3.9, count: 2, id: id(3) },
      { boost: 1, rating: 4.1, count: 9, id: id(4) },
      { boost: 0, rating: 5, count: 90, id: id(0) },
    ];
    expect([...rows].sort(compareDirectory).map((r) => r.id)).toEqual([id(3), id(4), id(2), id(0), id(1)]);
  });

  it('insights: conversion per unique visitor, capped at 100 %', () => {
    expect(insightsSummary(40, 20, 5)).toEqual({ days: 30, views: 40, uniqueVisitors: 20, requests: 5, conversion: 0.25 });
    expect(insightsSummary(0, 0, 0).conversion).toBe(0);
    expect(insightsSummary(3, 2, 9).conversion).toBe(1);
  });

  it('counselor plans upgrade and downgrade like member plans', () => {
    const at = new Date('2026-12-01');
    expect(classifyChange({ plan: 'PRO_PLUS', expiresAt: at, pendingPlan: null }, { plan: 'PRO_PREMIUM', expiresAt: at, pendingPlan: null })).toBe('upgrade');
    expect(classifyChange({ plan: 'PRO_PREMIUM', expiresAt: at, pendingPlan: null }, { plan: 'PRO_PLUS', expiresAt: at, pendingPlan: null })).toBe('downgrade');
  });
});
