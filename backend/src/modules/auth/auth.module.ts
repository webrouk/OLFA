import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Put } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ApiBearerAuth, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { ENV, Env } from '../../config/env';
import { AllowPending, AuthUser, CurrentUser, OlfaRequest, Public, RateLimit, Req } from '../../common/http';
import { OtpChallengeResponse, PushTokenDto, RefreshDto, RequestOtpDto, TokensResponse, VerifyOtpDto } from './auth.dto';
import { AuthService } from './auth.service';
import { LogSmsProvider, SMS_PROVIDER, TwilioSmsProvider } from './sms.provider';
import { pickLocale } from '../../domain/locale';

@ApiTags('auth')
@Controller('v1/auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('otp/request')
  @HttpCode(200)
  @ApiOkResponse({ type: OtpChallengeResponse })
  request(@Body() dto: RequestOtpDto, @Req() req: OlfaRequest) {
    // SMS in the phone's language: Arabic, English or French; anything else → English.
    return this.auth.requestOtp(dto, req.ipHash, pickLocale(req.headers['accept-language']));
  }

  @Public()
  @RateLimit(20, 600)
  @Post('otp/verify')
  @HttpCode(200)
  @ApiOkResponse({ type: TokensResponse })
  verify(@Body() dto: VerifyOtpDto, @Req() req: OlfaRequest) {
    return this.auth.verifyOtp(dto, { ipHash: req.ipHash, userAgent: req.headers['user-agent'], locale: pickLocale(req.headers['accept-language']) });
  }

  @Public()
  @RateLimit(30, 60)
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @ApiBearerAuth()
  @AllowPending()
  @Post('logout')
  @HttpCode(204)
  async logout(@CurrentUser() u: AuthUser) {
    await this.auth.logout(u.sessionId);
  }

  @ApiBearerAuth()
  @AllowPending()
  @Get('sessions')
  sessions(@CurrentUser() u: AuthUser) {
    return this.auth.listSessions(u.id, u.sessionId);
  }

  @ApiBearerAuth()
  @AllowPending()
  @Delete('sessions/:id')
  @HttpCode(204)
  async revoke(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.auth.revokeSession(u.id, id);
  }

  @ApiBearerAuth()
  @AllowPending()
  @Put('push-token')
  @HttpCode(204)
  async pushToken(@CurrentUser() u: AuthUser, @Body() dto: PushTokenDto) {
    await this.auth.setPushToken(u.sessionId, dto.fcmToken);
  }
}

@Module({
  imports: [JwtModule.register({})],
  controllers: [AuthController],
  providers: [
    AuthService,
    TwilioSmsProvider,
    LogSmsProvider,
    {
      provide: SMS_PROVIDER,
      inject: [ENV, TwilioSmsProvider, LogSmsProvider],
      useFactory: (env: Env, twilio: TwilioSmsProvider, log: LogSmsProvider) => (env.SMS_PROVIDER === 'twilio' ? twilio : log),
    },
  ],
  exports: [JwtModule],
})
export class AuthModule {}
