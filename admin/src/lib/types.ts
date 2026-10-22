export type Role = 'doctor' | 'nutritionist' | 'trainer';
export type ApplicationStatus = 'pending' | 'approved' | 'rejected';

export interface Me {
  uid: string;
  email: string;
  role: Role | 'admin' | 'user';
  roleLabel: string;
}

export interface AdminSpecialist {
  uid: string;
  email: string;
  name: string;
  type: Role;
  specialty: string;
  fees: { video: number; chat: number } | null;
  available: boolean;
  rating: number;
  reviewCount: number;
}

export interface AdminApplication {
  uid: string;
  status: ApplicationStatus;
  email: string;
  name: string;
  type: Role;
  specialty: string;
  licenseNumber: string;
  yearsOfExperience: number;
  fees: { video: number; chat: number } | null;
  submittedAt: number;
  rejectReason: string;
}

export interface NewSpecialistResult {
  uid: string;
  created: boolean;
  email: string;
  resetLink: string;
}

export interface Money { count: number; amount: number }

export interface PaymentSummary {
  count: number;
  earned: Money;
  upcoming: Money;
  held: Money;
  clinicDue: Money;
  due: Money;
  refunded: Money;
  platformFees: number;
  gross: number;
  testPayments: number;
}

export interface Overview {
  specialists: { total: number; doctor: number; nutritionist: number; trainer: number };
  applications: { pending: number };
  appointments: { total: number; byStatus: Record<string, number> };
  payments: { gross: number; platformFees: number; refunded: Money; refundsDue: Money; clinicDue: Money; held: Money; testPayments: number; count: number };
  calls: { sessions: number; minutes: number };
  messages: { conversations: number; total: number };
}

export type PaymentBucket = 'held' | 'upcoming' | 'earned' | 'clinic' | 'due' | 'refunded';

export interface PaymentRow {
  appointmentId: string;
  patientId: string;
  patientName: string;
  specialistId: string;
  specialistName: string;
  startAt: number;
  status: string;
  type: 'video' | 'chat';
  bucket: PaymentBucket | 'void' | 'unpaid';
  payment: { status: 'paid' | 'pay_at_clinic'; method: 'card' | 'wallet' | 'clinic' | null; total: number; consultationFee: number; platformFee: number; paidAt: number; test: boolean; transactionId: string } | null;
  refund: { status: 'refunded' | 'manual'; amount: number; at: number; reason: string; by: 'specialist' | 'admin' | 'system' } | null;
}

export interface SpecialistPayments { specialistId: string; name: string; summary: PaymentSummary }

export interface DeleteResult {
  cancelled: number;
  accountDeleted: boolean;
  keptMemberAccount: boolean;
}
