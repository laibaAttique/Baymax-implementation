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

export interface Overview {
  specialists: { total: number; doctor: number; nutritionist: number; trainer: number };
  applications: { pending: number };
  appointments: { total: number; byStatus: Record<string, number> };
}

export interface DeleteResult {
  cancelled: number;
  accountDeleted: boolean;
  keptMemberAccount: boolean;
}
