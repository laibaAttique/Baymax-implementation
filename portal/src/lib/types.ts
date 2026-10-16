export type Role = 'doctor' | 'nutritionist' | 'trainer';
export type Status = 'requested' | 'confirmed' | 'completed' | 'cancelled' | 'no_show' | 'declined';
export type Phase = 'upcoming' | 'live' | 'past' | 'cancelled' | 'requested' | 'expired' | 'declined';

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
  declineReason: string;
  phase: Phase;
  canRespond: boolean;
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
  verified?: boolean;
  fees: { video: number; chat: number };
  available: boolean;
  emergency?: boolean;
  tzOffsetMinutes: number;
  availability: Availability;
}

export type ApplicationStatus = 'pending' | 'approved' | 'rejected';

export interface MyApplication {
  status: ApplicationStatus;
  name: string;
  type: Role;
  specialty: string;
  submittedAt: number;
  rejectReason: string;
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

export interface Me {
  uid: string;
  email: string;
  /** `user` = signed in but not a specialist (yet): the registration screens apply. */
  role: Role | 'admin' | 'user';
  roleLabel: string;
  /** Null for an administrator, who has no specialist profile. */
  profile: SpecialistProfile | null;
  application?: MyApplication | null;
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

export interface NewSpecialistResult {
  uid: string;
  created: boolean;
  email: string;
  resetLink: string;
}

export interface Dashboard {
  serverTime: number;
  greeting: string;
  name: string;
  role: Role;
  roleLabel: string;
  counts: { consultationsToday: number; upcoming7Days: number; patients: number; awaitingNotes: number; pendingRequests: number };
  requests: Appointment[];
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

export interface PlanAuthor {
  uid: string;
  name: string;
  role: Role;
}

export interface DietPlan {
  status: 'approved' | 'modified';
  note: string;
  targetKcal?: number;
  proteinG?: number;
  carbsG?: number;
  fatG?: number;
  avoid: string[];
  tips: string[];
  by: PlanAuthor;
  at: number;
}

export interface WorkoutItem {
  exerciseId: string;
  sets: number;
  reps?: number;
  seconds?: number;
  note?: string;
}

export interface WorkoutDayPlan {
  day: number;
  rest: boolean;
  items: WorkoutItem[];
}

export interface WorkoutPlan {
  status: 'approved' | 'modified';
  note: string;
  schedule: WorkoutDayPlan[];
  by: PlanAuthor;
  at: number;
}

export interface LibraryExercise {
  id: string;
  name: string;
  group: string;
  level: number;
  timed: boolean;
  baseReps: number;
  baseSeconds: number;
}

export interface PatientSummary {
  patientId: string;
  name: string;
  appointments: number;
  lastVisit: number | null;
  nextVisit: number | null;
  notesWritten: number;
  canEditPlans: boolean;
}

export interface DietReviewItem {
  date: string;
  status: 'approved' | 'flagged';
  note: string;
  at: number;
}

export interface PatientRecord {
  patient: { id: string; name: string };
  appointments: {
    id: string;
    startAt: number;
    status: Status;
    type: 'video' | 'chat';
    durationMinutes: number;
    consultation: Consultation | null;
    payment: Appointment['payment'];
  }[];
  plans: { diet: DietPlan | null; workout: WorkoutPlan | null };
  patientChoice: { diet: 'baymax' | 'specialist'; workout: 'baymax' | 'specialist' };
  reviews: DietReviewItem[];
  access: { canEditDiet: boolean; canEditWorkout: boolean; canReviewDiet: boolean; planEditDays: number };
  sharedData: SharedData | null;
  sharedLocked: string | null;
}

export interface Prescription {
  appointmentId: string;
  patientName: string;
  startAt: number;
  prescription: string;
  updatedAt: number;
}
