export type Role = 'doctor' | 'nutritionist' | 'trainer';
export type Status = 'confirmed' | 'completed' | 'cancelled' | 'no_show';
export type Phase = 'upcoming' | 'live' | 'past' | 'cancelled';

export interface Consultation {
  notes: string;
  prescription: string;
  updatedAt: number;
  updatedBy: string;
}

export interface Appointment {
  id: string;
  patientId: string;
  patientName: string;
  specialistName: string;
  role: Role;
  specialty: string;
  startAt: number;
  endAt: number;
  durationMinutes: number;
  type: 'video' | 'chat';
  status: Status;
  fee: number;
  meetingLink: string;
  notesForSpecialist: string;
  shares: { healthSummary: boolean; foodLog7d: boolean; activity30d: boolean };
  consultation: Consultation | null;
  payment: { status: 'paid' | 'pay_at_clinic'; method: 'card' | 'wallet' | 'clinic' | null; total: number; test: boolean; transactionId: string } | null;
  phase: Phase;
  canJoin: boolean;
  canPrepare: boolean;
  canViewShared: boolean;
  live: boolean;
}

export interface Availability {
  days: number[];
  start: string;
  end: string;
  slotMinutes: number;
}

export interface SpecialistProfile {
  name: string;
  type: Role;
  specialty: string;
  bio?: string;
  yearsOfExperience?: number;
  rating?: number;
  reviewCount?: number;
  fees: { video: number; chat: number };
  available: boolean;
  emergency?: boolean;
  tzOffsetMinutes: number;
  availability: Availability;
}

export interface Me {
  uid: string;
  email: string;
  role: Role;
  roleLabel: string;
  profile: SpecialistProfile;
}

export interface Dashboard {
  serverTime: number;
  greeting: string;
  name: string;
  role: Role;
  roleLabel: string;
  counts: { consultationsToday: number; upcoming7Days: number; patients: number; awaitingNotes: number };
  today: Appointment[];
}

export interface SharedData {
  healthSummary?: {
    fullName: string;
    age: number | null;
    gender: string | null;
    height: { value: number; unit: string } | null;
    weight: { value: number; unit: string } | null;
    targetWeight: { value: number; unit: string } | null;
    primaryGoal: string | null;
    activityLevel: string | null;
    workoutFrequency: number | null;
    bmi: number | null;
    healthClassification: string | null;
    medicalConditions: string[];
    foodAllergies: string[];
    medications: string;
  } | null;
  foodLog7d?: { date: string; totalKcal: number; entries: { meal: string; name: string; kcal: number; protein: number; carbs: number; fat: number }[] }[];
  activity30d?: { date: string; minutes: number | null; kcal: number | null }[];
}

export interface AppointmentDetail {
  serverTime: number;
  appointment: Appointment;
  sharedData: SharedData | null;
  sharedLocked: string | null;
}
