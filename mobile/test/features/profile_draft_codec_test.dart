import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/features/profile/domain/profile_draft.dart';
import 'package:olfa/shared/models/models.dart';

void main() {
  test('sign-up answers survive a save and restore', () {
    final d = const ProfileDraft().copyWith(
      gender: Gender.female,
      name: 'Sara',
      birthDate: DateTime(1997, 4, 2),
      countryIso: 'SA',
      city: 'Riyadh',
      maritalStatus: MaritalStatus.neverMarried,
      education: Education.master,
      occupation: 'architect',
      heightCm: () => 165,
      timeline: MarriageTimeline.within1Year,
      bio: 'A long enough biography for the profile.',
      interests: {'reading', 'travel'},
      prefAgeMin: 27,
      prefAgeMax: 35,
      prefMarital: {MaritalStatus.neverMarried, MaritalStatus.divorced},
      prefWantsChildren: () => null,
      photoSlots: [true, true, false, false, false, false],
      photoIds: ['p1', 'p2', null, null, null, null],
      photoRightsConfirmed: true,
      accountType: AccountType.member,
      religion: () => 'islam',
      sect: () => 'islam.sunni',
      religionConsent: true,
      prefReligions: {'islam'},
    );
    final back = ProfileDraftCodec.decode(ProfileDraftCodec.encode(d))!;
    expect(back.gender, Gender.female);
    expect(back.name, 'Sara');
    expect(back.birthDate, DateTime(1997, 4, 2));
    expect(back.city, 'Riyadh');
    expect(back.education, Education.master);
    expect(back.heightCm, 165);
    expect(back.interests, {'reading', 'travel'});
    expect(back.prefMarital, {MaritalStatus.neverMarried, MaritalStatus.divorced});
    expect(back.prefWantsChildren, isNull);
    expect(back.photoIds, ['p1', 'p2', null, null, null, null]);
    expect(back.photoCount, 2);
    expect(back.sect, 'islam.sunni');
    expect(back.religionValid, isTrue);
  });

  test('damaged or older data starts fresh instead of crashing', () {
    expect(ProfileDraftCodec.decode({'v': 99, 'name': 'x'}), isNull);
    expect(ProfileDraftCodec.decode({'v': 1, 'birthDate': 12, 'photoSlots': 'no', 'gender': 'other'})?.gender, isNull);
  });

  test('active filter count drives the badge and "Show results · n filters"', () {
    expect(const DiscoverFilters().activeCount, 0);
    expect(const DiscoverFilters(ageMin: 25, city: 'Dubai', interests: {'reading'}).activeCount, 3);
    expect(const DiscoverFilters(height: (160, 180), religions: {'islam'}, sects: {'islam.sunni'}).activeCount, 2);
  });
}
